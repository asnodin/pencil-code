! $Id$
!
!  Isentropic initial condition (density, entropy) for convection in
!  spherical coordinates. Produces an isentropic stratification with
!  given surface gravity and surface temperature, and a heat
!  conduction profile proportional to r^-15. The setup was originally
!  introduced in Astron. Nachr., 332, 883.
!
!  02-sep-13/pete: coded
!
!** AUTOMATIC CPARAM.INC GENERATION ****************************
! Declare (for generation of cparam.inc) the number of f array
! variables and auxiliary variables added by this module
!
! CPARAM logical, parameter :: linitial_condition = .true.
!
!***************************************************************
!
module InitialCondition
!
  use Cparam
  use Cdata
  use General, only: keep_compiler_quiet
  use Messages
  use EquationOfState
  use Sub, only: step, der_step
!
  implicit none
!
  include '../initial_condition.h'
!
  real :: star_luminosity=1.0, Rstar=1.0, Rtran=1.2, chit0=1e8
  real :: xi0=1.0, npoly1=1.5, npoly_jump=1.0, nad=1.5
  real :: npoly_fac=1.0, npoly_exp=1.0, r_ss=1.0,chiSGS_top=1.0
  real :: Fbottom, wtran=0.02,Tcor_jump=1.0
  logical :: lcorona=.false., lwrite_cooling_profile=.false.
  logical :: lref_state=.false.
  character (len=labellen) :: strat_type='polytropic'
!
  namelist /initial_condition_pars/ &
      star_luminosity, Rstar, nad, npoly1, npoly_jump, xi0, & 
      lcorona, Rtran, wtran, Tcor_jump, strat_type, r_ss, npoly_fac, &
      npoly_exp, chiSGS_top, chit0, lwrite_cooling_profile, lref_state
!
  contains
!***********************************************************************
    subroutine register_initial_condition()
!
!  Register variables associated with this module; likely none.
!
!  07-may-09/wlad: coded
!
      if (lroot) call svn_id( &
           "$Id$")
!
    endsubroutine register_initial_condition
!***********************************************************************
    subroutine initialize_initial_condition(f)
!
!  Initialize any module variables which are parameter dependent.
!
!  07-may-09/wlad: coded
!
      real, dimension (mx,my,mz,mfarray) :: f
!
      call keep_compiler_quiet(f)
!
    endsubroutine initialize_initial_condition
!***********************************************************************
    subroutine initial_condition_all(f)
!
!  Initializes all the f arrays in one call. This subroutine is called last.
!
!  02-sep-13/pete: coded
!  06-oct-13/joern: add coronal layer
!  25-jan-15/MR: extended case 'polytropic' to linear density
!
      use SharedVariables, only: get_shared_variable
      use EquationOfState, only: gamma, gamma_m1, rho0, cs20
      use General, only: safe_character_assign
      use Mpicomm, only: stop_it, mpiallreduce_sum
      use FArrayManager
!
      real, dimension (mx,my,mz,mfarray), intent(inout) :: f
!
      real, dimension (mx) :: TT, TTc, rho_prof, dTdr, dTdr_cor, dlnTdr 
      real, dimension (mx) :: lnrho, ss_prof, cs2_prof, dlnrhodr
      real, dimension (nxgrid) :: kappa, gkappa, npoly2, gnpoly2
      real, dimension (nxgrid) :: rho_global, TT_global, TTc_global, dTdr_global, dTdrc_global
      real, dimension (nxgrid) :: dlnTdr_global, dlnrhodr_global, lnrho_global
      real, dimension (nxgrid) :: ss_global, cs2_global
      real, dimension (nxgrid) :: drhodr_global, del2rho_global
      real :: T00, rho00, Rsurf, Tsurf, coef1, L00, sigma, cs2_surf, cs2_top
      real :: cs2_bot
      real :: Tcor, Rmin, wmin, cs2_cor, rho_surf
      real :: Lsun=3.84e26, Rsun=7e8, Omsun=2.7e-6, Msun=2e30, cvsun=20786.1
      real :: GG=6.67348e-11, rhosun=200., fluxratio, Omsim, gratio, rratio
      real :: T00sun=2.23e6
      real :: meanrho, volume, total_mass, tmp
      real, pointer :: gravx, cp, cv
      integer :: i, j, n, m, q, ix, ierr, unit=1, nsurf, nsurf_global
!
      character (len=120) :: wfile
!
!     Retrieve cp, cv, and gravx
!
      call get_shared_variable('cp', cp, ierr)
      if (ierr/=0) call stop_it(" initialize_initial_condition: "//&
           "there was a problem when getting cp")
      call get_shared_variable('cv', cv, ierr)
      if (ierr/=0) call stop_it(" initialize_initial_condition: "//&
           "there was a problem when getting cv")
      call get_shared_variable('gravx', gravx, ierr)
      if (ierr/=0) call stop_it(" initialize_initial_condition: "//&
           "there was a problem when getting gravx")
!
!  Select type of stratification
!
      select case (strat_type)
!
!  Single polytrope for the convection zone
!
      case ('polytropic')
!
!  Surface of the star
!
      if (lcorona) then
         Rsurf=Rstar
         if (x0+Lxyz(1)<=Rstar) then
           write(unit=errormsg,fmt=*) &
           'initial_condition: your wedge has to have a radius bigger than Rstar'//& 
           ' for using a corona'
           call fatal_error('initial_condition',errormsg)
         endif
         Rtran=Rtran*Rstar
         wtran=wtran*Rstar
         Rmin=Rsurf+(Rtran-Rsurf)/6.
         wmin=wtran/2.0
         if (iproc .eq. root) then
           print*,'initial_condition: you are using a coronal envelope'
         endif
         do i=1,nx
           if (x(l1+i)>=Rsurf) then
             nsurf=i-1
             exit
           endif
         enddo
         do j=1, nxgrid
           if (xglobal(nghost+j)>=Rsurf) then
             nsurf_global=j
             exit
           endif
         enddo
      else
         Rsurf=x0+Lxyz(1)
         nsurf=l2-l1
         nsurf_global=nxgrid
      endif
!
!  Temperature using a constant polytropic index npoly1
!
      TT=gravx/(cv*(gamma-1.))*(xi0/Rstar + 1./(npoly1+1.)*(1./x - 1./Rsurf))
      TT_global=gravx/(cv*(gamma-1.))*(xi0/Rstar + 1./(npoly1+1.)*(1./xglobal(nghost+1:nxgrid+nghost) - 1./Rsurf))
      dTdr_global=-gravx/xglobal(nghost+1:nxgrid+nghost)**2./(cv*(gamma-1)*(npoly1+1.))
      T00=gravx/(cv*(gamma-1.))*(xi0/Rstar + 1./(npoly1+1.)*(1./x0 - 1./Rsurf))
      Tsurf=gravx/(cv*(gamma-1.))*xi0/Rstar
!
      if (lcorona) then
!
!  Using a step function for the temperature profile in the corona,
!  and another step function to make a smooth transition.
!
        Tcor=Tcor_jump*T00
        TTc=0
        TTc(l1+nsurf:mx)=Tsurf+(Tcor-Tsurf)*step(x(l1+nsurf:mx),Rtran,wtran)
        TT(l1+nsurf:mx)=TT(l1+nsurf:mx)+(TTc(l1+nsurf:mx)-TT(l1+nsurf:mx))*step(x(l1+nsurf:mx), Rmin, wmin)
!
!  global temperature
!
        TTc_global(nsurf_global:nxgrid)=Tsurf+(Tcor-Tsurf)*step(xglobal(nghost+nsurf_global:nxgrid+nghost),Rtran,wtran)
        TT_global(nsurf_global:nxgrid)=TT_global(nsurf_global:nxgrid) + & 
                                      (TTc_global(nsurf_global:nxgrid)-TT_global(nsurf_global:nxgrid))* & 
                                      step(xglobal(nghost+nsurf_global:nxgrid+nghost), Rmin, wmin)
!
!  global temperature derivative
!
        dTdr_global=-gravx/xglobal(nghost+1:nxgrid+nghost)**2./(cv*(gamma-1)*(npoly1+1.))
        dTdrc_global=0
        dTdrc_global(nsurf_global:nxgrid)=(Tcor-Tsurf)*der_step(xglobal(nghost+nsurf_global:nxgrid+nghost),Rtran,wtran)
        dTdr_global(nsurf_global:nxgrid)=dTdr_global(nsurf_global:nxgrid)+(dTdrc_global(nsurf_global:nxgrid) - & 
             dTdr_global(nsurf_global:nxgrid))*step(xglobal(nghost+nsurf_global:nxgrid+nghost), Rmin, wmin) + &
             (TTc_global(nsurf_global:nxgrid)-TT_global(nsurf_global:nxgrid)) * &
             der_step(xglobal(nghost+nsurf_global:nxgrid+nghost),Rmin, wmin)
        dlnTdr_global=dTdr_global/TT_global
      endif
!
!  Density stratification assuming an isentropic atmosphere with ss=0. 
!
      rho_prof=rho0*(TT/T00)**(1./(gamma-1.))
      rho00=rho0*(T00/T00)**(1./(gamma-1.))
      rho_surf=rho0*(Tsurf/T00)**(1./(gamma-1.))
      rho_global=rho0*(TT_global/T00)**(1./(gamma-1.))
      drhodr_global=(1./(gamma-1.))*rho_global*dTdr_global/TT_global
      del2rho_global=(1./(gamma-1.))*(drhodr_global*dTdr_global/TT_global - &
           rho_global*(dTdr_global/TT_global)**2. + &
           rho_global*2.*gravx/(xglobal(nghost+1:nxgrid+nghost)**3.)/ &
           (cv*(gamma-1.)*(npoly1+1.)*TT_global)) + &
           (2./xglobal(nghost+1:nxgrid+nghost))*drhodr_global
!
      lnrho=log(rho_prof/rho0)
      lnrho_global=log(rho_global/rho0)
!
      if (lcorona) then
        dlnrhodr_global=-dlnTdr_global-gravx/xglobal(nghost+1:nxgrid+nghost)**2/(cv*(gamma-1)*TT_global)
        do j=nsurf_global-nsurf_global/10, nxgrid
          lnrho_global(j)=lnrho_global(j-1)+dlnrhodr_global(j-1)*(xglobal(nghost+j)-xglobal(nghost+j-1))
        enddo
        lnrho(l1:l2)=lnrho_global(ipx*nx+1:(ipx+1)*nx)
      endif
!
!  Renormalize entropy with rho0 and cs20
!
      cs2_prof=cs20*TT*cv*gamma*(gamma-1.)
      cs2_global=cs20*TT_global*cv*gamma*(gamma-1.)
      ss_prof=log(cs2_prof/cs20)/gamma - & 
              (gamma-1.)/(gamma)*(lnrho-log(rho0))
      ss_global=log(cs2_global/cs20)/gamma - & 
              (gamma-1.)/(gamma)*(lnrho_global-log(rho0))
!
!  Put lnrho and ss into the f-array
!
      if (lref_state) then
         f(l1:l2,:,:,ilnrho) = 0.
         f(l1:l2,:,:,iss) = 0.
!
         if (iproc .eq. root) then 
           call safe_character_assign(wfile,'reference_state.dat')
           open(unit,file=wfile,status='unknown')
           do ix=1,nxgrid
              write(unit,'(4(2x,1pe15.8))') rho_global(ix),drhodr_global(ix),del2rho_global(ix),ss_global(1)
           enddo
           close(unit)
         endif
!
      else
        do m=m1,m2
        do n=n1,n2
          if (ldensity_nolog) then
            f(l1:l2,m,n,irho) = exp(lnrho(l1:l2))
          else
            f(l1:l2,m,n,ilnrho) = lnrho(l1:l2)
          endif
          f(l1:l2,m,n,iss) = ss_prof(l1:l2)
        enddo
        enddo
      endif
!
!  Compute hcond and glhcond using global x-array
!
      coef1=star_luminosity*rho0*sqrt(gravx*Rstar)*cv*(gamma-1.)/(4.*pi)
!
      do n=1,nxgrid
        npoly2(n)=npoly_jump*(xglobal(nghost+n)/x0)**(-15.)+nad-npoly_jump
        gnpoly2(n)=15./xglobal(nghost+n)*(nad-npoly_jump-npoly2(n))
       if ((xglobal(nghost+n)>=Rstar) .and. & 
            ((npoly2(n)+1)/exp(lnrho_global(n))>2*(npoly2(1)+1)/exp(lnrho_global(1)))) then
          npoly2(n)=2*(npoly2(1)+1)*exp(lnrho_global(n)-lnrho_global(1))-1
          gnpoly2(n)=2*(npoly2(1)+1)*exp(lnrho_global(n)-lnrho_global(1))*dlnrhodr_global(n)
        endif
      enddo
!
      kappa=coef1*(npoly2+1.)
      gkappa=coef1*gnpoly2
!
!  Thermal equilibrium condition
!
      case ('thermal_equilibrium')
!
!  Compute hcond and glhcond using global x-array
!
        coef1=star_luminosity*rho0*sqrt(gravx*Rstar)*cv*(gamma-1.)/(4.*pi)
!
        do n=1,nxgrid
           npoly2(n)=npoly_jump*(xglobal(nghost+n)/x0)**(-15.)+nad-npoly_jump
           gnpoly2(n)=15./xglobal(nghost+n)*(nad-npoly_jump-npoly2(n))
        enddo
!
        kappa=coef1*(npoly2+1.)
        gkappa=coef1*gnpoly2
      endselect
!
!  Write kappa and gkappa to file to be read by run.in
!
      if (iproc .eq. root) then 
         call safe_character_assign(wfile,'hcond_glhc.dat')
         open(unit,file=wfile,status='unknown')
         do ix=1,nxgrid
            write(unit,'(2(2x,1pe12.5))') kappa(ix),gkappa(ix)
         enddo
         close(unit)
      endif
!
!  Write cs2 to a file to be used in cooling
!
      if (lwrite_cooling_profile) then
        if (iproc .eq. root) then 
           call safe_character_assign(wfile,'cooling_profile.dat')
           open(unit,file=wfile,status='unknown')
           do ix=1,nxgrid
              write(unit,'(3(2x,1pe17.10))') cs2_global(ix)
           enddo
           close(unit)
        endif
      endif
!
!  Compute flux at the bottom and a modified Stefan-Boltzmann constant
!  assuming the the total flux at the outer boundary radiates through
!  the surface for the Fgs boundary condition.
!
      L00=star_luminosity*rho0*gravx**1.5*sqrt(Rstar)
      Fbottom=L00/(4.*pi*x0**2)
      sigma=(L00/(4.*pi*Rsurf**2))/Tsurf**4
      cs2_bot=T00*cv*gamma*(gamma-1.)
      cs2_top=Tsurf*cv*gamma*(gamma-1.)
      if (lcorona) then
        cs2_top=TT_global(nxgrid)*cv*gamma*(gamma-1.)
        cs2_surf=Tsurf*cv*gamma*(gamma-1.)
        cs2_cor=Tcor*cv*gamma*(gamma-1.)
      endif

!
!  Compute the ratio of the dimensionless luminosity in the simulation
!  versus the Sun in order to determine a rotation rate for the
!  simulation which reproduces the rotational effect in the Sun.
!
      fluxratio=star_luminosity*rhosun*(GG*Msun)**1.5*sqrt(Rsun)/Lsun
      gratio=gravx/(GG*Msun)
      rratio=Rsun/Rstar
      Omsim=fluxratio**(1./3.)*sqrt(gratio)*rratio**(1.5)*Omsun
      chiSGS_top=sqrt(gratio)*fluxratio**(1./3.)*chit0/sqrt(rratio)
!
!  Compute total mass.
!
      total_mass=0.
!
      do n=n1,n2
        tmp=0.
        do m=m1,m2
          tmp=tmp+sum(exp(lnrho(l1:l2))*dVol_x(l1:l2))*dVol_y(m)
        enddo
        total_mass=total_mass+tmp*dVol_z(n)
      enddo
!
      if (ncpus>1) then
        call mpiallreduce_sum(total_mass,tmp)
        total_mass=tmp
      endif
!
      volume=((x0+Lxyz(1))**3-x0**3)*(cos(y0)-cos(y0+Lxyz(2)))*((z0+Lxyz(3))-z0)/3.
!
      if (iproc .eq. root) then
         print*,''
         print*,'initial_condition: Fbottom    =',Fbottom
         print*,'initial_condition: SigmaSBt   =',sigma
         print*,'initial_condition: cs2bot     =',cs2_bot
         print*,'initial_condition: cs2top     =',cs2_top
         print*,'initial_condition: fluxratio  =',fluxratio
         print*,'initial_condition: Omsim      =',Omsim
         print*,'initial_condition: chiSGS_top =',chiSGS_top
         print*,'initial_condition: gratio     =',gratio
         print*,'initial_condition: rratio     =',rratio
         print*,'initial_condition: volume     =',volume
         print*,'initial_condition: total_mass =',total_mass
         if (lcorona) then
           print*, ''
           print*,'initial_condition: rcool      =',Rsurf+(Rtran-Rsurf)/6.
           print*,'initial_condition: wcool      =',wmin/1.5
           print*,'initial_condition: cs2cool    =',cs2_surf*0.85
           print*,'initial_condition: rcool2     =',Rtran
           print*,'initial_condition: wcool2     =',wtran
           print*,'initial_condition: cs2cool2   =',cs2_cor
         endif
         print*,''
!
!  Compute temperatures at the surface and in the corona assuming solar
!  temperature at the base of the convection zone.
!
         print*,'initial_condition: Temperature at the surface                 =',Tsurf*T00sun/T00, 'K'
         print*,'initial_condition: Temperature at the bottom                  =',T00sun, 'K'
         if (lcorona) then
           print*,'initial_condition: Temperature in the corona                  =',Tcor*T00sun/T00, 'K'
         endif
         print*,'initial_condition: Density stratification in convection zone  =',rho00/rho_surf
         if (lcorona) then
           print*,'initial_condition: Density stratification in the corona       =',&
                exp(lnrho_global(nsurf_global)-lnrho_global(nxgrid))
           print*,'initial_condition: Density stratification with corona         =',exp(log(rho00)-lnrho_global(nxgrid))
         endif
         print*,'initial_condition: Turbulent heat conductivity at the surface =',chit0, 'm^2/s'
         print*,''
      endif
!
    endsubroutine initial_condition_all
!***********************************************************************
    subroutine initial_condition_uu(f)
!
!  Initialize the velocity field.
!
!  07-may-09/wlad: coded
!
      real, dimension (mx,my,mz,mfarray), intent(inout) :: f
!
!  SAMPLE IMPLEMENTATION
!
      call keep_compiler_quiet(f)
!
    endsubroutine initial_condition_uu
!***********************************************************************
    subroutine initial_condition_lnrho(f)
!
!  Initialize logarithmic density. init_lnrho will take care of
!  converting it to linear density if you use ldensity_nolog.
!
!  07-may-09/wlad: coded
!
      real, dimension (mx,my,mz,mfarray), intent(inout) :: f
!
!  SAMPLE IMPLEMENTATION
!
      call keep_compiler_quiet(f)
!
    endsubroutine initial_condition_lnrho
!***********************************************************************
    subroutine initial_condition_ss(f)
!
!  Initialize entropy.
!
!  07-may-09/wlad: coded
!
      use EquationOfState, only: gamma,gamma_m1,gamma1,cs20,rho0,lnrho0
!
      real, dimension (mx,my,mz,mfarray), intent(inout) :: f
!
!  SAMPLE IMPLEMENTATION
!
      call keep_compiler_quiet(f)
!
    endsubroutine initial_condition_ss
!********************************************************************
    subroutine read_initial_condition_pars(unit,iostat)
!
!  07-may-09/wlad: coded
!
      include '../unit.h'
      integer, intent(inout), optional :: iostat
!
      if (present(iostat)) then
        read(unit,NML=initial_condition_pars,ERR=99, IOSTAT=iostat)
      else
        read(unit,NML=initial_condition_pars,ERR=99)
      endif
!
99    return
!
    endsubroutine read_initial_condition_pars
!***********************************************************************
    subroutine write_initial_condition_pars(unit)
!
      integer, intent(in) :: unit
!
      write(unit,NML=initial_condition_pars)
!
    endsubroutine write_initial_condition_pars
!***********************************************************************
!
!********************************************************************
!************        DO NOT DELETE THE FOLLOWING       **************
!********************************************************************
!**  This is an automatically generated include file that creates  **
!**  copies dummy routines from noinitial_condition.f90 for any    **
!**  InitialCondition routines not implemented in this file        **
!**                                                                **
    include '../initial_condition_dummies.inc'
!********************************************************************
endmodule InitialCondition
