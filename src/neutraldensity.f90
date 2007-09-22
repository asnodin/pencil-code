! $Id: neutraldensity.f90,v 1.13 2007-09-22 13:56:54 wlyra Exp $

!  This module is used both for the initial condition and during run time.
!  It contains dlnrho_dt and init_lnrho, among other auxiliary routines.

!** AUTOMATIC CPARAM.INC GENERATION ****************************
! Declare (for generation of cparam.inc) the number of f array
! variables and auxiliary variables added by this module
!
!
! MVAR CONTRIBUTION 1
! MAUX CONTRIBUTION 0
!
! PENCILS PROVIDED lnrhon,rhon,rhon1,glnrhon,grhon,unglnrhon,ungrhon
! PENCILS PROVIDED del2lnrhon,del2rhon,glnrhon2
! PENCILS PROVIDED del6lnrhon,del6rhon,snglnrhon
!
!***************************************************************

module NeutralDensity

  use Cparam
  use Cdata
  use Messages
!  use EquationOfState, only: cs0,cs20,lnrho0,rho0, &
!                             gamma,gamma1,cs2top,cs2bot, &
!                             mpoly,beta_glnrho_global

  implicit none

  include 'neutraldensity.h'
  
  real :: kx_lnrhon=1.,ky_lnrhon=1.,kz_lnrhon=1.
  real :: ampllnrhon=0.,rhon_left=1.,rhon_right=1.
  real :: diffrhon=0.,diffrhon_hyper3=0.,diffrhon_shock=0.
  real :: lnrhon_const=0., rhon_const=1.
  real :: lnrhon_int=0.,lnrhon_ext=0.
  real, dimension(3) :: diffrhon_hyper3_aniso=0.
  integer, parameter :: ndiff_max=4
  logical :: lmass_source=.false.,lcontinuity_neutral=.true.
  logical :: lupw_lnrhon=.false.,lupw_rhon=.false.
  logical :: ldiffn_normal=.false.,ldiffn_hyper3=.false.,ldiffn_shock=.false.
  logical :: ldiffn_hyper3lnrhon=.false.,ldiffn_hyper3_aniso=.false.
  logical :: lfreeze_lnrhonint=.false.,lfreeze_lnrhonext=.false.
  logical :: lneutraldensity_nolog=.false.

  character (len=labellen), dimension(ninit) :: initlnrhon='nothing'
  character (len=labellen), dimension(ndiff_max) :: idiffn=''
  character (len=labellen) :: borderlnrhon='nothing'
  character (len=5) :: iinit_str
!
  integer :: iglobal_gg=0
  integer :: iglobal_rhon=0
!
  real :: lnrhon0,lnrhon_left,lnrhon_right,alpha,zeta

  namelist /neutraldensity_init_pars/ &
       ampllnrhon,initlnrhon,    &
       rhon_left,rhon_right,lnrhon_const,rhon_const, &
       idiffn,lneutraldensity_nolog,    &
       lcontinuity_neutral,lnrhon0,lnrhon_left,lnrhon_right, &
       alpha,zeta,kx_lnrhon,ky_lnrhon,kz_lnrhon

  namelist /neutraldensity_run_pars/ &
       diffrhon,diffrhon_hyper3,diffrhon_shock,   &
       lupw_lnrhon,lupw_rhon,idiffn,     &
       lnrhon_int,lnrhon_ext, &
       lfreeze_lnrhonint,lfreeze_lnrhonext,         &
       lnrhon_const,lcontinuity_neutral,borderlnrhon,    &
       diffrhon_hyper3_aniso,alpha,zeta

  ! diagnostic variables (needs to be consistent with reset list below)
  integer :: idiag_rhonm=0,idiag_rhon2m=0,idiag_lnrhon2m=0
  integer :: idiag_rhonmin=0,idiag_rhonmax=0,idiag_unglnrhonm=0
  integer :: idiag_lnrhonmphi=0,idiag_rhonmphi=0,idiag_dtnd=0
  integer :: idiag_rhonmz=0, idiag_rhonmy=0, idiag_rhonmx=0
  integer :: idiag_rhonmxy=0, idiag_rhonmr=0
  integer :: idiag_neutralmass=0

  contains

!***********************************************************************
    subroutine register_neutraldensity()
!
!  Initialise variables which should know that we solve the
!  compressible hydro equations: ilnrhon; increase nvar accordingly.
!
!  28-feb-07/wlad: adapted from density
!
      use Sub
      use FArrayManager
!
      logical, save :: first=.true.
!      integer, target :: tmp_ilnrhon
!
      if (.not. first) call fatal_error('register_neutraldensity','module registration called twice')
      first = .false.
!
      if (.not.lcartesian_coords) call fatal_error('register_neutraldensity','non cartesian '//&
           'not yet implemented in the neutrals module')
!
      call farray_register_pde('lnrhon',ilnrhon)
!      
      lneutraldensity=.true.
!
!  identify version number (generated automatically by CVS)
!
      if (lroot) call cvs_id( &
           "$Id: neutraldensity.f90,v 1.13 2007-09-22 13:56:54 wlyra Exp $")
!
    endsubroutine register_neutraldensity
!***********************************************************************
    subroutine initialize_neutraldensity()
!
!  Perform any post-parameter-read initialization i.e. calculate derived
!  parameters.
!
!  For compatibility with other applications, we keep the possibility
!  of giving diffrhon units of dxmin*cs0, but cs0 is not well defined general
!
!  28-feb-07/wlad: adapted
!
!
      use CData, only: lfreeze_varext,lfreeze_varint,lreloading,ilnrhon
      use FArrayManager
!      use EquationOfState, only: select_eos_variable
!
      integer :: i
      logical :: lnothing
!
!  Turn off continuity equation term for 0-D runs.
!
      if (nxgrid*nygrid*nzgrid==1) then
        lcontinuity_neutral=.false.
        print*, 'initialize_neutraldensity: 0-D run, turned off continity equation'
      endif
!
!  Initialize dust diffusion
!
      ldiffn_normal=.false.
      ldiffn_shock=.false.
      ldiffn_hyper3=.false.
      ldiffn_hyper3lnrhon=.false.
      ldiffn_hyper3_aniso=.false.
!
      lnothing=.false.
!
      do i=1,ndiff_max
        select case (idiffn(i))
        case ('normal')
          if (lroot) print*,'diffusion: div(D*grad(rhon))'
          ldiffn_normal=.true.
        case ('hyper3')
          if (lroot) print*,'diffusion: (d^6/dx^6+d^6/dy^6+d^6/dz^6)rhon'
          ldiffn_hyper3=.true.
        case ('hyper3lnrhon')
          if (lroot) print*,'diffusion: (d^6/dx^6+d^6/dy^6+d^6/dz^6)lnrhon'
          ldiffn_hyper3lnrhon=.true.
       case ('hyper3_aniso')
          if (lroot) print*,'diffusion: (Dx*d^6/dx^6 + Dy*d^6/dy^6 + Dz*d^6/dz^6)rhon'
          ldiffn_hyper3_aniso=.true.
        case ('shock')
          if (lroot) print*,'diffusion: shock diffusion'
          ldiffn_shock=.true.
        case ('')
          if (lroot .and. (.not. lnothing)) print*,'diffusion: nothing'
        case default
          write(unit=errormsg,fmt=*) 'initialize_neutraldensity: ', &
              'No such value for idiff(',i,'): ', trim(idiffn(i))
          call fatal_error('initialize_neutraldensity',errormsg)
        endselect
        lnothing=.true.
      enddo
!
!  If we're timestepping, die or warn if the the diffusion coefficient that
!  corresponds to the chosen diffusion type is not set.
!
      if (lrun) then
        if (ldiffn_normal.and.diffrhon==0.0) &
            call warning('initialize_neutraldensity', &
            'Diffusion coefficient diffrhon is zero!')
        if ( (ldiffn_hyper3 .or. ldiffn_hyper3lnrhon) &
            .and. diffrhon_hyper3==0.0) &
            call fatal_error('initialize_neutraldensity', &
            'Diffusion coefficient diffrhon_hyper3 is zero!')
        if ( (ldiffn_hyper3_aniso) .and.  &
             ((diffrhon_hyper3_aniso(1)==0. .and. nxgrid/=1 ).or. &
              (diffrhon_hyper3_aniso(2)==0. .and. nygrid/=1 ).or. &
              (diffrhon_hyper3_aniso(3)==0. .and. nzgrid/=1 )) ) &
            call fatal_error('initialize_neutraldensity', &
            'A diffusion coefficient of diffrhon_hyper3 is zero!')
        if (ldiffn_shock .and. diffrhon_shock==0.0) &
            call fatal_error('initialize_neutraldensity', &
            'diffusion coefficient diffrhon_shock is zero!')
      endif
!
!  Hyperdiffusion only works with (not log) density. One must either use
!  ldensity_nolog=T or work with GLOBAL =   global_nolog_density.
!
      if ((ldiffn_hyper3.or.ldiffn_hyper3_aniso) .and. (.not. lneutraldensity_nolog)) then
        if (lroot) print*,"initialize_neutraldensity: Creating global array for rhon to use hyperdiffusion"
        call farray_register_global('rhon',iglobal_rhon)
      endif
!
      if (lfreeze_lnrhonint) lfreeze_varint(ilnrhon) = .true.
      if (lfreeze_lnrhonext) lfreeze_varext(ilnrhon) = .true.
!
! Tell the equation of state that we're here and what f variable we use
!
! WL: need an equation of state!!
!
        !if (lneutraldensity_nolog) then
        !  call select_eos_variable('rhon',ilnrhon)
        !else
        !  call select_eos_variable('lnrhon',ilnrhon)
        !endif
!
! Ionization-Recombination equilibrium is usually the case
!      
    endsubroutine initialize_neutraldensity
!***********************************************************************
    subroutine read_neutraldensity_init_pars(unit,iostat)
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat

      if (present(iostat)) then
        read(unit,NML=neutraldensity_init_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=neutraldensity_init_pars,ERR=99)
      endif


99    return
    endsubroutine read_neutraldensity_init_pars
!***********************************************************************
    subroutine write_neutraldensity_init_pars(unit)
      integer, intent(in) :: unit

      write(unit,NML=neutraldensity_init_pars)

    endsubroutine write_neutraldensity_init_pars
!***********************************************************************
    subroutine read_neutraldensity_run_pars(unit,iostat)
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat

      if (present(iostat)) then
        read(unit,NML=neutraldensity_run_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=neutraldensity_run_pars,ERR=99)
      endif

99    return
    endsubroutine read_neutraldensity_run_pars
!***********************************************************************
    subroutine write_neutraldensity_run_pars(unit)
      integer, intent(in) :: unit

      write(unit,NML=neutraldensity_run_pars)

    endsubroutine write_neutraldensity_run_pars
!***********************************************************************
    subroutine init_lnrhon(f,xx,yy,zz)
!
!  initialise lnrhon; called from start.f90
!
!  28-feb-07/wlad: adapted
!
      use General, only: chn,complex_phase
      use Gravity, only: zref,z1,z2,gravz,nu_epicycle,potential, &
                          lnumerical_equilibrium
      use Selfgravity,only: rhs_poisson_const
      use Initcond
      use Initcond_spec
      use IO
      use Mpicomm
      use Sub
      use EquationOfState
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my,mz) :: xx,yy,zz,tmp,pot,prof
      real :: lnrhonint,cs2int,pot0
      real :: pot_ext,cs2_ext,tmp1,k_j2
      real :: zbot,ztop,haut,TT
      real, dimension (nx) :: r_mn,lnrhon,lnTT,ss
      logical :: lnothing
      complex :: omega_jeans

!
!  define bottom and top height
!
      zbot=xyz0(3)
      ztop=xyz0(3)+Lxyz(3)
!
!  Set default values for sound speed at top and bottom.
!  These may be updated in one of the following initialization routines.
!
      cs2top=cs20; cs2bot=cs20
!
!  different initializations of lnrhon (called from start).
!  If initrhon does't match, f=0 is assumed (default).
!
      lnothing=.true.

      do iinit=1,ninit

         if (initlnrhon(iinit)/='nothing') then

            lnothing=.false.

            call chn(iinit,iinit_str)

            select case(initlnrhon(iinit))
!
! some one-liners from density
!
            case('zero', '0'); f(:,:,:,ilnrhon)=0.
            case('const_lnrhon'); f(:,:,:,ilnrhon)=lnrhon_const
            case('const_rhon'); f(:,:,:,ilnrhon)=log(rhon_const)
            case('constant'); f(:,:,:,ilnrhon)=log(rhon_left)
            case('sinwave-z'); call sinwave(ampllnrhon,f,ilnrhon,kz=kz_lnrhon)
            case('gaussian-noise')
               if (lnrhon_left /= 0.) f(:,:,:,ilnrhon)=lnrhon_left
               call gaunoise(ampllnrhon,f,ilnrhon,ilnrhon)
               !case('globaldisc')
               !minimum mass solar nebula
               !  if (lroot)  print*,'init_lnrhon: initialize initial condition for Keplerian global disc'
               !  call power_law(f,iglobal_gg,plaw,ptlaw,lstratified)
            case default
               !
               !  Catch unknown values
               !
               write(unit=errormsg,fmt=*) 'No such value for initlnrhon(' &
                    //trim(iinit_str)//'): ',trim(initlnrhon(iinit))
               call fatal_error('init_lnrhon',errormsg)
               
            endselect

            if (lroot) print*,'init_lnrhon: initlnrhon(' &
                 //trim(iinit_str)//') = ',trim(initlnrhon(iinit))

         endif
         
      enddo

      if (lnothing.and.lroot) print*,'init_lnrhon: nothing'
!
!  If unlogarithmic density considered, take exp of lnrhon resulting from
!  initlnrhon
!
      if (lneutraldensity_nolog) f(:,:,:,ilnrhon)=exp(f(:,:,:,ilnrhon))
!
!  sanity check
!
      if (notanumber(f(l1:l2,m1:m2,n1:n2,ilnrhon))) then
        call error('init_lnrhon', 'Imaginary density values')
      endif
!
    endsubroutine init_lnrhon
!***********************************************************************
    subroutine pencil_criteria_neutraldensity()
!
!  All pencils that the NeutralDensity module depends on are specified here.
!
!  28-feb-07/wlad: adapted
!
      use Cdata
!
!  always needed for ionization and recombination
!      
      lpenc_requested(i_rho)  =.true.
      lpenc_requested(i_rhon) =.true.
!
      if (.not.lneutraldensity_nolog) then
        lpenc_requested(i_rho1) =.true.
        lpenc_requested(i_rhon1)=.true.
      endif
!
      if (lcontinuity_neutral) then
        lpenc_requested(i_divun)=.true.
        if (lneutraldensity_nolog) then
          lpenc_requested(i_ungrhon)=.true.
        else
          lpenc_requested(i_unglnrhon)=.true.
        endif
      endif
      if (ldiffn_shock) then
        lpenc_requested(i_shock)=.true.
        lpenc_requested(i_gshock)=.true.
        if (lneutraldensity_nolog) then
          lpenc_requested(i_grhon)=.true.
          lpenc_requested(i_del2rhon)=.true.
        else
          lpenc_requested(i_glnrhon)=.true.
          lpenc_requested(i_glnrhon2)=.true.
          lpenc_requested(i_del2lnrhon)=.true.
        endif
      endif
      if (ldiffn_normal) then
        if (lneutraldensity_nolog) then
          lpenc_requested(i_del2rhon)=.true.
        else
          lpenc_requested(i_glnrhon2)=.true.
          lpenc_requested(i_del2lnrhon)=.true.
        endif
      endif
      if (ldiffn_hyper3.or.ldiffn_hyper3_aniso) lpenc_requested(i_del6rhon)=.true.
      if (ldiffn_hyper3.and..not.lneutraldensity_nolog) lpenc_requested(i_rhon)=.true.
      if (ldiffn_hyper3lnrhon) lpenc_requested(i_del6lnrhon)=.true.
!
      if (lmass_source) lpenc_requested(i_rcyl_mn)=.true.
!
      lpenc_diagnos2d(i_lnrhon)=.true.
      lpenc_diagnos2d(i_rhon)=.true.
!
      if (idiag_rhonm/=0 .or. idiag_rhonmz/=0 .or. idiag_rhonmy/=0 .or. &
           idiag_rhonmx/=0 .or. idiag_rhon2m/=0 .or. idiag_rhonmin/=0 .or. &
           idiag_rhonmax/=0 .or. idiag_rhonmxy/=0 .or. idiag_neutralmass/=0) &
           lpenc_diagnos(i_rhon)=.true.
      if (idiag_lnrhon2m/=0) lpenc_diagnos(i_lnrhon)=.true.
      if (idiag_unglnrhonm/=0) lpenc_diagnos(i_unglnrhon)=.true.
!
    endsubroutine pencil_criteria_neutraldensity
!***********************************************************************
    subroutine pencil_interdep_neutraldensity(lpencil_in)
!
!  Interdependency among pencils from the NeutralDensity module is 
!    specified here.
!
!  28-feb-07/wlad: adapted
!
      logical, dimension(npencils) :: lpencil_in
!
      if (lneutraldensity_nolog) then
        if (lpencil_in(i_rhon1)) lpencil_in(i_rhon)=.true.
      else
        if (lpencil_in(i_rhon)) lpencil_in(i_rhon1)=.true.
      endif
      if (lpencil_in(i_unglnrhon)) then
        lpencil_in(i_uun)=.true.
        lpencil_in(i_glnrhon)=.true.
      endif
      if (lpencil_in(i_ungrhon)) then
        lpencil_in(i_uun)=.true.
        lpencil_in(i_grhon)=.true.
      endif
      if (lpencil_in(i_glnrhon2)) lpencil_in(i_glnrhon)=.true.
      if (lpencil_in(i_snglnrhon)) then
        lpencil_in(i_snij)=.true.
        lpencil_in(i_glnrhon)=.true.
      endif
!  The pencils glnrhon and grhon come in a bundle.
      if (lpencil_in(i_glnrhon) .and. lpencil_in(i_grhon)) then
        if (lneutraldensity_nolog) then
          lpencil_in(i_grhon)=.false.
        else
          lpencil_in(i_glnrhon)=.false.
        endif
      endif
!
    endsubroutine pencil_interdep_neutraldensity
!***********************************************************************
    subroutine calc_pencils_neutraldensity(f,p)
!
!  Calculate NeutralDensity pencils.
!  Most basic pencils should come first, as others may depend on them.
!
!  28-feb-07/wlad: adapted
!
      use Sub, only: grad,dot,dot2,u_dot_grad,del2,del6,multmv,g2ij
!
      real, dimension (mx,my,mz,mfarray) :: f
      type (pencil_case) :: p
!
      integer :: i, mm, nn
!
      intent(inout) :: f,p
! lnrhon
      if (lpencil(i_lnrhon)) then
        if (lneutraldensity_nolog) then
          p%lnrhon=log(f(l1:l2,m,n,ilnrhon))
        else
          p%lnrhon=f(l1:l2,m,n,ilnrhon)
        endif
      endif
! rhon1 and rhon
      if (lneutraldensity_nolog) then
        if (lpencil(i_rhon)) p%rhon=f(l1:l2,m,n,ilnrhon)
        if (lpencil(i_rhon1)) p%rhon1=1.0/p%rhon
      else
        if (lpencil(i_rhon1)) p%rhon1=exp(-f(l1:l2,m,n,ilnrhon))
        if (lpencil(i_rhon)) p%rhon=1.0/p%rhon1
      endif
! glnrhon and grhon
      if (lpencil(i_glnrhon).or.lpencil(i_grhon)) then
        if (lneutraldensity_nolog) then
          call grad(f,ilnrhon,p%grhon)
          if (lpencil(i_glnrhon)) then
            do i=1,3
              p%glnrhon(:,i)=p%grhon(:,i)/p%rhon
            enddo
          endif
        else
          call grad(f,ilnrhon,p%glnrhon)
          if (lpencil(i_grhon)) then
            do i=1,3
              p%grhon(:,i)=p%rhon*p%glnrhon(:,i)
            enddo
          endif
        endif
      endif
! unglnrhon
      if (lpencil(i_unglnrhon)) then
        if (lneutraldensity_nolog) then
          call dot(p%uun,p%glnrhon,p%unglnrhon)
        else
          call u_dot_grad(f,ilnrhon,p%glnrhon,p%uun,p%unglnrhon,UPWIND=lupw_lnrhon)
        endif
      endif
! ungrhon
      if (lpencil(i_ungrhon)) then
        if (lneutraldensity_nolog) then
          call u_dot_grad(f,ilnrhon,p%grhon,p%uun,p%ungrhon,UPWIND=lupw_rhon)
        else
          call dot(p%uun,p%grhon,p%ungrhon)
        endif
      endif
! glnrhon2
      if (lpencil(i_glnrhon2)) call dot2(p%glnrhon,p%glnrhon2)
! del2lnrhon
      if (lpencil(i_del2lnrhon)) then
        if (lneutraldensity_nolog) then
          if (headtt) then
            call fatal_error('calc_pencils_neutraldensity', &
                             'del2lnrhon not available for non-logarithmic mass density')
          endif
        else
          call del2(f,ilnrhon,p%del2lnrhon)
        endif
      endif
! del2rhon
      if (lpencil(i_del2rhon)) then
        if (lneutraldensity_nolog) then
          call del2(f,ilnrhon,p%del2rhon)
        else
          if (headtt) then
            call fatal_error('calc_pencils_neutraldensity', &
                             'del2rhon not available for logarithmic mass density')
          endif
        endif
      endif
! del6rhon
      if (lpencil(i_del6rhon)) then
        if (lneutraldensity_nolog) then
          call del6(f,ilnrhon,p%del6rhon)
        else
          if (lfirstpoint) then
            !
            ! Fill global rhon array using the ilnrhon data
!ajwm This won't work unless earlt_finalize is used... ?
            if (iglobal_rhon/=0) then
              do mm=1,my; do nn=1,mz
                f(:,mm,nn,iglobal_rhon) = exp(f(:,mm,nn,ilnrhon))
              enddo; enddo
            else
              call fatal_error("calc_pencils_neutraldensity",&
                       "A global rhon slot must be available for calculating del6rhon from lnrhon")
            endif
          endif
          if (iglobal_rhon/=0) call del6(f,iglobal_rhon,p%del6rhon)
        endif
      endif
! del6lnrhon
      if (lpencil(i_del6lnrhon)) then
        if (lneutraldensity_nolog) then
          if (headtt) then
            call fatal_error('calc_pencils_neutraldensity', &
                             'del6lnrhon not available for non-logarithmic mass density')
          endif
        else
          call del6(f,ilnrhon,p%del6lnrhon)
        endif
      endif
! snglnrhon
      if (lpencil(i_snglnrhon)) call multmv(p%snij,p%glnrhon,p%snglnrhon)
!
    endsubroutine calc_pencils_neutraldensity
!***********************************************************************
    subroutine dlnrhon_dt(f,df,p)
!
!  continuity equation
!  calculate dlnrhon/dt = - un.gradlnrhon - divun
!
!  28-feb-07/wlad: adapted
!
      use Mpicomm, only: stop_it
      use Sub
!
      real, dimension (mx,my,mz,mfarray) :: f
      real, dimension (mx,my,mz,mvar) :: df
      type (pencil_case) :: p
!
      real, dimension (nx) :: fdiff, gshockglnrhon, gshockgrhon, tmp
!
      intent(in)  :: f,p
      intent(out) :: df
!
!  identify module and boundary conditions
!
      if (headtt.or.ldebug) print*,'dlnrhon_dt: SOLVE dlnrhon_dt'
      if (headtt) call identify_bcs('lnrhon',ilnrhon)
!
!  continuity equation
!
      if (lcontinuity_neutral) then
        if (lneutraldensity_nolog) then
          df(l1:l2,m,n,ilnrhon) = df(l1:l2,m,n,ilnrhon) - p%ungrhon   - p%rhon*p%divun
        else
          df(l1:l2,m,n,ilnrhon) = df(l1:l2,m,n,ilnrhon) - p%unglnrhon - p%divun
        endif
      endif
!
!  Ionization and recombination
!
      if (lneutraldensity_nolog) then
         df(l1:l2,m,n,ilnrhon) = df(l1:l2,m,n,ilnrhon) - zeta*p%rhon        + alpha*p%rho**2
         df(l1:l2,m,n,ilnrho ) = df(l1:l2,m,n,ilnrho ) + zeta*p%rhon        - alpha*p%rho**2
      else
         df(l1:l2,m,n,ilnrhon) = df(l1:l2,m,n,ilnrhon) - zeta               + alpha*p%rho**2*p%rhon1
         df(l1:l2,m,n,ilnrho ) = df(l1:l2,m,n,ilnrho ) + zeta*p%rhon*p%rho1 - alpha*p%rho
      endif
!
!  Mass diffusion
!
      fdiff=0.0
!
      if (ldiffn_normal) then  ! Normal diffusion operator
        if (lneutraldensity_nolog) then
          fdiff = fdiff + diffrhon*p%del2rhon
        else
          fdiff = fdiff + diffrhon*(p%del2lnrhon+p%glnrhon2)
        endif
        if (lfirst.and.ldt) diffus_diffrhon=diffus_diffrhon+diffrhon*dxyz_2
        if (headtt) print*,'dlnrhon_dt: diffrhon=', diffrhon
      endif
!
!  Hyper diffusion
!
      if (ldiffn_hyper3) then
        if (lneutraldensity_nolog) then
          fdiff = fdiff + diffrhon_hyper3*p%del6rhon
        else
          fdiff = fdiff + 1/p%rhon*diffrhon_hyper3*p%del6rhon
        endif
        if (lfirst.and.ldt) diffus_diffrhon=diffus_diffrhon+diffrhon_hyper3*dxyz_6
        if (headtt) print*,'dlnrhon_dt: diffrhon_hyper3=', diffrhon_hyper3
      endif
!
      if (ldiffn_hyper3_aniso) then
         if (lneutraldensity_nolog) then
            call del6fj(f,diffrhon_hyper3_aniso,ilnrhon,tmp)
            fdiff = fdiff + tmp
            if (lfirst.and.ldt) diffus_diffrhon=diffus_diffrhon+&
                 diffrhon_hyper3_aniso(1)*dx_1(l1:l2)**6 + &
                 diffrhon_hyper3_aniso(2)*dy_1(m)**6 + &
                 diffrhon_hyper3_aniso(3)*dz_1(n)**6
            if (headtt) &
                 print*,'dlnrhon_dt: diffrhon_hyper3=(Dx,Dy,Dz)=',diffrhon_hyper3_aniso
         else
            call stop_it("anisotropic hyperdiffusion not implemented for lnrhon")
         endif
      endif
!
      if (ldiffn_hyper3lnrhon) then
        if (.not. lneutraldensity_nolog) then
          fdiff = fdiff + diffrhon_hyper3*p%del6lnrhon
        endif
        if (lfirst.and.ldt) diffus_diffrhon=diffus_diffrhon+diffrhon_hyper3*dxyz_6
        if (headtt) print*,'dlnrhon_dt: diffrhon_hyper3=', diffrhon_hyper3
      endif
!
!  Shock diffusion
!
      if (ldiffn_shock) then
        if (lneutraldensity_nolog) then
          call dot_mn(p%gshock,p%grhon,gshockgrhon)
          df(l1:l2,m,n,ilnrhon) = df(l1:l2,m,n,ilnrhon) + &
              diffrhon_shock*p%shock*p%del2rhon + diffrhon_shock*gshockgrhon
        else
          call dot_mn(p%gshock,p%glnrhon,gshockglnrhon)
          df(l1:l2,m,n,ilnrhon) = df(l1:l2,m,n,ilnrhon) + &
              diffrhon_shock*p%shock*(p%del2lnrhon+p%glnrhon2) + &
              diffrhon_shock*gshockglnrhon
        endif
        if (lfirst.and.ldt) &
            diffus_diffrhon=diffus_diffrhon+diffrhon_shock*p%shock*dxyz_2
        if (headtt) print*,'dlnrhon_dt: diffrhon_shock=', diffrhon_shock
      endif
!
!  Add diffusion term to continuity equation
!
      df(l1:l2,m,n,ilnrhon) = df(l1:l2,m,n,ilnrhon) + fdiff
      if (headtt.or.ldebug) &
          print*,'dlnrhon_dt: max(diffus_diffrhon) =', maxval(diffus_diffrhon)
!
!  Apply border profile
!
      if (lborder_profiles) call set_border_neutraldensity(f,df,p)
!
!  2d-averages
!  Note that this does not necessarily happen with ldiagnos=.true.
!
      if (l2davgfirst) then
        if (idiag_rhonmxy/=0)    call zsum_mn_name_xy(p%rhon,idiag_rhonmxy)
        call phisum_mn_name_rz(p%lnrhon,idiag_lnrhonmphi)
        call phisum_mn_name_rz(p%rhon,idiag_rhonmphi)
      endif
!
!  1d-averages. Happens at every it1d timesteps, NOT at every it1
!
      if (l1ddiagnos) then
         if (idiag_rhonmr/=0)    call phizsum_mn_name_r(p%rhon,idiag_rhonmr)
         if (idiag_rhonmz/=0)    call xysum_mn_name_z(p%rhon,idiag_rhonmz)
         if (idiag_rhonmx/=0)    call yzsum_mn_name_x(p%rhon,idiag_rhonmx)
         if (idiag_rhonmy/=0)    call xzsum_mn_name_y(p%rhon,idiag_rhonmy)
      endif
!
!  Calculate density diagnostics
!
      if (ldiagnos) then
        if (idiag_rhonm/=0)     call sum_mn_name(p%rhon,idiag_rhonm)
        if (idiag_neutralmass/=0)  call sum_lim_mn_name(p%rhon,idiag_neutralmass,p)
        if (idiag_rhonmin/=0) &
            call max_mn_name(-p%rhon,idiag_rhonmin,lneg=.true.)
        if (idiag_rhonmax/=0)   call max_mn_name(p%rhon,idiag_rhonmax)
        if (idiag_rhon2m/=0)    call sum_mn_name(p%rhon**2,idiag_rhon2m)
        if (idiag_lnrhon2m/=0)  call sum_mn_name(p%lnrhon**2,idiag_lnrhon2m)
        if (idiag_unglnrhonm/=0) call sum_mn_name(p%unglnrhon,idiag_unglnrhonm)
        if (idiag_dtnd/=0) &
            call max_mn_name(diffus_diffrhon/cdtv,idiag_dtnd,l_dt=.true.)
      endif
!
    endsubroutine dlnrhon_dt
!***********************************************************************
    subroutine get_recombine_and_ionize_coeff(alpha_,zeta_)
!
      real :: alpha_,zeta_
!
      alpha_=alpha;zeta_=zeta
!
    endsubroutine get_recombine_and_ionize_coeff
!***********************************************************************
    subroutine set_border_neutraldensity(f,df,p)
!
!  Calculates the driving term for the border profile
!  of the lnrhon variable.
!
!  28-jul-06/wlad: coded
!
      use BorderProfiles, only: border_driving
      use EquationOfState, only: cs0,cs20
!
      real, dimension(mx,my,mz,mfarray) :: f
      type (pencil_case) :: p
      real, dimension(mx,my,mz,mvar) :: df
      real, dimension(nx) :: f_target,OO_sph,OO_cyl,cs,theta
      real :: r0_pot=0.1
      integer :: i
!
      select case(borderlnrhon)
!
      case('zero','0')
         f_target=0.
      case('constant')
         f_target=lnrhon_const
      case('stratification')
         !OO_sph = sqrt((r_mn**2 + r0_pot**2)**(-1.5))
         !OO_cyl = sqrt((rcyl_mn**2 + r0_pot**2)**(-1.5))
         !cs = OO_cyl*rcyl_mn*cs0
         !f_target=lnrhon_const - 0.5*(theta/cs0)**2
         f_target=(p%rcyl_mn-p%r_mn)/(cs20*p%r_mn)
      case('nothing')
         if (lroot.and.ip<=5) &
              print*,"set_border_neutraldensity: borderlnrhon='nothing'"
      case default
         write(unit=errormsg,fmt=*) &
              'set_border_neutraldensity: No such value for borderlnrhon: ', &
              trim(borderlnrhon)
         call fatal_error('set_border_neutraldensity',errormsg)
      endselect
!
      if (lneutraldensity_nolog) f_target=exp(f_target)
!
      if (borderlnrhon /= 'nothing') then
        call border_driving(f,df,p,f_target,ilnrhon)
      endif
!
    endsubroutine set_border_neutraldensity
!***********************************************************************
    subroutine rprint_neutraldensity(lreset,lwrite)
!
!  reads and registers print parameters relevant for compressible part
!
!  28-feb-07/wlad: adapted
!
      use Sub
!
      logical :: lreset
      logical, optional :: lwrite
!
      integer :: iname, inamex, inamey, inamez, inamexy, irz, inamer
      logical :: lwr
!
      lwr = .false.
      if (present(lwrite)) lwr=lwrite
!
!  reset everything in case of reset
!  (this needs to be consistent with what is defined above!)
!
      if (lreset) then
        idiag_rhonm=0; idiag_rhon2m=0; idiag_lnrhon2m=0; idiag_unglnrhonm=0
        idiag_rhonmin=0; idiag_rhonmax=0; idiag_dtnd=0
        idiag_lnrhonmphi=0; idiag_rhonmphi=0
        idiag_rhonmz=0; idiag_rhonmy=0; idiag_rhonmx=0 
        idiag_rhonmxy=0; idiag_rhonmr=0; idiag_neutralmass=0
        diffrhon=0.
      endif
!
!  iname runs through all possible names that may be listed in print.in
!
      if(lroot.and.ip<14) print*,'rprint_neutraldensity: run through parse list'
      do iname=1,nname
        call parse_name(iname,cname(iname),cform(iname),'rhonm',idiag_rhonm)
        call parse_name(iname,cname(iname),cform(iname),'rhon2m',idiag_rhon2m)
        call parse_name(iname,cname(iname),cform(iname),'rhonmin',idiag_rhonmin)
        call parse_name(iname,cname(iname),cform(iname),'rhonmax',idiag_rhonmax)
        call parse_name(iname,cname(iname),cform(iname),'lnrhon2m',idiag_lnrhon2m)
        call parse_name(iname,cname(iname),cform(iname),'unglnrhonm',idiag_unglnrhonm)
        call parse_name(iname,cname(iname),cform(iname),'dtnd',idiag_dtnd)
        call parse_name(iname,cname(iname),cform(iname),'neutralmass',idiag_neutralmass)
      enddo
!
!  check for those quantities for which we want xy-averages
!
      do inamez=1,nnamez
        call parse_name(inamez,cnamez(inamez),cformz(inamez),'rhonmz',idiag_rhonmz)
      enddo
!
!  check for those quantities for which we want xz-averages
!
      do inamey=1,nnamey
        call parse_name(inamey,cnamey(inamey),cformy(inamey),'rhonmy',idiag_rhonmy)
      enddo
!
!  check for those quantities for which we want yz-averages
!
      do inamex=1,nnamex
        call parse_name(inamex,cnamex(inamex),cformx(inamex),'rhonmx',idiag_rhonmx)
      enddo
!
!  check for those quantities for which we want phiz-averages
!
      do inamer=1,nnamer
        call parse_name(inamer,cnamer(inamer),cformr(inamer),'rhonmr',idiag_rhonmr)
      enddo
!
!  check for those quantities for which we want z-averages
!
      do inamexy=1,nnamexy
        call parse_name(inamexy,cnamexy(inamexy),cformxy(inamexy),'rhonmxy',idiag_rhonmxy)
      enddo
!
!  check for those quantities for which we want phi-averages
!
      do irz=1,nnamerz
        call parse_name(irz,cnamerz(irz),cformrz(irz),&
            'lnrhonmphi',idiag_lnrhonmphi)
        call parse_name(irz,cnamerz(irz),cformrz(irz),'rhonmphi',idiag_rhonmphi)
      enddo
!
!  write column where which density variable is stored
!
      if (lwr) then
        write(3,*) 'i_rhonm=',idiag_rhonm
        write(3,*) 'i_rhon2m=',idiag_rhon2m
        write(3,*) 'i_rhonmin=',idiag_rhonmin
        write(3,*) 'i_rhonmax=',idiag_rhonmax
        write(3,*) 'i_lnrhon2m=',idiag_lnrhon2m
        write(3,*) 'i_unglnrhonm=',idiag_unglnrhonm
        write(3,*) 'i_rhonmz=',idiag_rhonmz
        write(3,*) 'i_rhonmy=',idiag_rhonmy
        write(3,*) 'i_rhonmx=',idiag_rhonmx
        write(3,*) 'nname=',nname
        write(3,*) 'ilnrhon=',ilnrhon
        write(3,*) 'i_lnrhonmphi=',idiag_lnrhonmphi
        write(3,*) 'i_rhonmphi=',idiag_rhonmphi
        write(3,*) 'i_rhonmr=',idiag_rhonmr
        write(3,*) 'i_dtnd=',idiag_dtnd
        write(3,*) 'i_neutralmass=',idiag_neutralmass
      endif
!
    endsubroutine rprint_neutraldensity
!***********************************************************************
endmodule NeutralDensity
