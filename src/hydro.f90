! $Id: hydro.f90,v 1.214 2005-08-20 14:47:29 dobler Exp $
!
!  This module takes care of everything related to velocity
!
!** AUTOMATIC CPARAM.INC GENERATION ****************************
! Declare (for generation of cparam.inc) the number of f array
! variables and auxiliary variables added by this module
!
! CPARAM logical, parameter :: lhydro = .true.
!
! MVAR CONTRIBUTION 3
! MAUX CONTRIBUTION 0
!
! PENCILS PROVIDED divu,oo,o2,ou,u2,uij,uu,sij,sij2,uij5,ugu
! PENCILS PROVIDED u2u13,del2u,del6u,graddivu
!
!***************************************************************
module Hydro

!  Note that Omega is already defined in cdata.

  use Cparam
  use Cdata, only: Omega, nu_turb, huge1
!!  use Density
  use Viscosity 
  use Messages

  implicit none

  include 'hydro.h'

  ! init parameters
  real :: widthuu=.1, radiusuu=1., urand=0., kx_uu=1., ky_uu=1., kz_uu=1.
  real :: uu_left=0.,uu_right=0.,uu_lower=1.,uu_upper=1.
  real :: uy_left=0.,uy_right=0.
  real :: initpower=1.,cutoff=0.
!ajwm  real :: nu_turb=0. !! MOVED TO CDATA
  real :: nu_turb0=0.,tau_nuturb=0.,nu_turb1=0.
  real, dimension (ninit) :: ampluu=0.0
  character (len=labellen), dimension(ninit) :: inituu='nothing'
  real, dimension(3) :: uu_const=(/0.,0.,0./)
  complex, dimension(3) :: coefuu=(/0.,0.,0./)
  real :: kep_cutoff_pos_ext= huge1,kep_cutoff_width_ext=0.0
  real :: kep_cutoff_pos_int=-huge1,kep_cutoff_width_int=0.0
  real :: u_out_kep=0.0
  integer :: N_modes_uu=0
  real :: star_offx=0.,star_offy=0.
  logical :: lcentrifugal_force=.false.

  namelist /hydro_init_pars/ &
       ampluu,inituu,widthuu, radiusuu,urand, &
       uu_left,uu_right,uu_lower,uu_upper,kx_uu,ky_uu,kz_uu,coefuu, &
       uy_left,uy_right,uu_const, Omega,initpower,cutoff, &
       nu_turb0, tau_nuturb, nu_turb1, &
       kep_cutoff_pos_ext,kep_cutoff_width_ext, &
       kep_cutoff_pos_int,kep_cutoff_width_int, &
       u_out_kep,N_modes_uu,lcentrifugal_force,star_offx,star_offy

  ! run parameters
  real :: theta=0.
  real :: tdamp=0.,dampu=0.,wdamp=0.
  real :: dampuint=0.0,dampuext=0.0,rdampint=-1e20,rdampext=impossible
  real :: tau_damp_ruxm=0.,tau_damp_ruym=0.,tau_diffrot1=0.
  real :: ampl_diffrot=0.,Omega_int=0.,xexp_diffrot=1.,kx_diffrot=1.
  real :: othresh=0.,othresh_per_orms=0.,orms=0.,othresh_scl=1.
  integer :: novec,novecmax=nx*ny*nz/4
  logical :: ldamp_fade=.false.,lOmega_int=.false.,lupw_uu=.false.
  logical :: lcalc_turbulence_pars=.false.
  logical :: lfreeze_uint=.false.,lfreeze_uext=.false.
!
! geodynamo
  namelist /hydro_run_pars/ &
       Omega,theta, &         ! remove and use viscosity_run_pars only
       tdamp,dampu,dampuext,dampuint,rdampext,rdampint,wdamp, &
       tau_damp_ruxm,tau_damp_ruym,tau_diffrot1,ampl_diffrot, &
       xexp_diffrot,kx_diffrot, &
       lOmega_int,Omega_int, ldamp_fade, lupw_uu, othresh,othresh_per_orms, &
       nu_turb0,tau_nuturb,nu_turb1,lcalc_turbulence_pars,lfreeze_uint, &
       lfreeze_uext,lcentrifugal_force

! end geodynamo

  ! other variables (needs to be consistent with reset list below)
  integer :: idiag_u2m=0,idiag_um2=0,idiag_oum=0,idiag_o2m=0
  integer :: idiag_uxpt=0,idiag_uypt=0,idiag_uzpt=0
  integer :: idiag_dtu=0,idiag_dtv=0,idiag_urms=0,idiag_umax=0
  integer :: idiag_uzrms=0,idiag_uzmax=0,idiag_orms=0,idiag_omax=0
  integer :: idiag_ux2m=0,idiag_uy2m=0,idiag_uz2m=0
  integer :: idiag_ox2m=0,idiag_oy2m=0,idiag_oz2m=0
  integer :: idiag_oxm=0,idiag_oym=0,idiag_ozm=0
  integer :: idiag_uxuym=0,idiag_uxuzm=0,idiag_uyuzm=0
  integer :: idiag_uxuymz=0,idiag_uxuzmz=0,idiag_uyuzmz=0
  integer :: idiag_oxoym=0,idiag_oxozm=0,idiag_oyozm=0
  integer :: idiag_ruxm=0,idiag_ruym=0,idiag_ruzm=0,idiag_rumax=0
  integer :: idiag_uxmz=0,idiag_uymz=0,idiag_uzmz=0,idiag_umx=0,idiag_umy=0
  integer :: idiag_umz=0,idiag_uxmxy=0,idiag_uymxy=0,idiag_uzmxy=0
  integer :: idiag_Marms=0,idiag_Mamax=0,idiag_divum=0,idiag_divu2m=0
  integer :: idiag_u2u13m=0,idiag_oumphi=0
  integer :: idiag_urmphi=0,idiag_upmphi=0,idiag_uzmphi=0,idiag_u2mphi=0
  integer :: idiag_fintm=0,idiag_fextm=0
  integer :: idiag_duxdzma=0,idiag_duydzma=0
  integer :: idiag_ekintot=0, idiag_ekin=0
  integer :: idiag_fmassz=0, idiag_fkinz=0

! Turbulence parameters
  real :: Hp,cs_ave,alphaSS,ul0,tl0,eps_diss,teta,ueta,tl01,teta1

  contains

!***********************************************************************
    subroutine register_hydro()
!
!  Initialise variables which should know that we solve the hydro
!  equations: iuu, etc; increase nvar accordingly.
!
!  6-nov-01/wolf: coded
!
      use Cdata
      use Mpicomm, only: stop_it
      use Sub
!
      logical, save :: first=.true.
!
      if (.not. first) call stop_it('register_hydro called twice')
      first = .false.
!
!ajwm      lhydro = .true.
!
      iuu = nvar+1             ! indices to access uu
      iux = iuu
      iuy = iuu+1
      iuz = iuu+2
      nvar = nvar+3             ! added 3 variables
!
      if ((ip<=8) .and. lroot) then
        print*, 'register_hydro: nvar = ', nvar
        print*, 'register_hydro: iux,iuy,iuz = ', iux,iuy,iuz
      endif
!
!  Put variable names in array
!
      varname(iux) = 'ux'
      varname(iuy) = 'uy'
      varname(iuz) = 'uz'
!
!  identify version number (generated automatically by CVS)
!
      if (lroot) call cvs_id( &
           "$Id: hydro.f90,v 1.214 2005-08-20 14:47:29 dobler Exp $")
!
      if (nvar > mvar) then
        if (lroot) write(0,*) 'nvar = ', nvar, ', mvar = ', mvar
        call stop_it('register_hydro: nvar > mvar')
      endif
!
!  Writing files for use with IDL
!
      if (lroot) then
        if (maux == 0) then
          if (nvar < mvar) write(4,*) ',uu $'
          if (nvar == mvar) write(4,*) ',uu'
        else
          write(4,*) ',uu $'
        endif
        write(15,*) 'uu = fltarr(mx,my,mz,3)*one'
      endif
!
    endsubroutine register_hydro
!***********************************************************************
    subroutine initialize_hydro(f,lstarting)
!
!  Perform any post-parameter-read initialization i.e. calculate derived
!  parameters.
!
!  24-nov-02/tony: coded 
!  13-oct-03/dave: check parameters and warn (if nec.) about velocity damping
!
      use Mpicomm, only: stop_it
      use CData,   only: r_int,r_ext,lfreeze_varint,lfreeze_varext,epsi,leos,iux,iuy,iuz
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      logical :: lstarting
!  
! Check any module dependencies
!
      if (.not. leos) then
        call stop_it('initialize_hydro: EOS=noeos but hydro requires an EQUATION OF STATE for the fluid')
      endif
!  r_int and r_ext override rdampint and rdampext if both are set
! 
      if (dampuint /= 0.) then
        if (r_int > epsi) then
          rdampint = r_int
        elseif (rdampint <= epsi) then
          write(*,*) 'initialize_hydro: inner radius not yet set, dampuint= ',dampuint
        endif 
      endif    

      if (dampuext /= 0.0) then      
        if (r_ext < impossible) then         
          rdampext = r_ext
        elseif (rdampext == impossible) then
          write(*,*) 'initialize_hydro: outer radius not yet set, dampuext= ',dampuext
        endif
      endif
!
      if (lfreeze_uint) lfreeze_varint(iux:iuz) = .true.
      if (lfreeze_uext) lfreeze_varext(iux:iuz) = .true.
!
      if (NO_WARN) print*,f,lstarting  !(to keep compiler quiet)
      endsubroutine initialize_hydro
!***********************************************************************
    subroutine read_hydro_init_pars(unit,iostat)
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat

      if (present(iostat)) then
        read(unit,NML=hydro_init_pars,ERR=99, IOSTAT=iostat)
      else 
        read(unit,NML=hydro_init_pars,ERR=99) 
      endif

99    return
    endsubroutine read_hydro_init_pars
!***********************************************************************
    subroutine write_hydro_init_pars(unit)
      integer, intent(in) :: unit
!
      write(unit,NML=hydro_init_pars)
    endsubroutine write_hydro_init_pars
!***********************************************************************
    subroutine read_hydro_run_pars(unit,iostat)
      integer, intent(in) :: unit
      integer, intent(inout), optional :: iostat

      if (present(iostat)) then
        read(unit,NML=hydro_run_pars,ERR=99, IOSTAT=iostat)
      else 
        read(unit,NML=hydro_run_pars,ERR=99) 
      endif

99    return
    endsubroutine read_hydro_run_pars
!***********************************************************************
    subroutine write_hydro_run_pars(unit)
      integer, intent(in) :: unit
!
      write(unit,NML=hydro_run_pars)
    endsubroutine write_hydro_run_pars
!***********************************************************************
    subroutine init_uu(f,xx,yy,zz)
!
!  initialise uu and lnrho; called from start.f90
!  Should be located in the Hydro module, if there was one.
!
!  07-nov-01/wolf: coded
!  24-nov-02/tony: renamed for consistance (i.e. init_[variable name])
!
      use Cdata
      use EquationOfState, only: cs20, gamma, beta_glnrho_scaled
      use General
      use Global
      use Gravity, only: grav_const,z1,g0,r0_pot,n_pot
      use Initcond
      use Mpicomm, only: stop_it
      use Sub
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz) :: r,p,tmp,xx,yy,zz,prof
      real :: kabs,crit
      integer :: j,i,l
!
!  inituu corresponds to different initializations of uu (called from start).
!
      do j=1,ninit

        select case(inituu(j))

        case('nothing'); if(lroot .and. j==1) print*,'init_uu: nothing'
        case('zero', '0')
          if(lroot) print*,'init_uu: zero velocity'
          ! Ensure really is zero, as may have used lread_oldsnap
          f(:,:,:,iux:iuz)=0. 
        case('const_uu'); do i=1,3; f(:,:,:,iuu+i-1) = uu_const(i); enddo
        case('keplerian'); call keplerian(f,g0,r0_pot,n_pot,xx,yy,zz &
           ,star_offx,star_offy)
        case('mode'); call modev(ampluu(j),coefuu,f,iuu,kx_uu,ky_uu,kz_uu,xx,yy,zz)
        case('gaussian-noise'); call gaunoise(ampluu(j),f,iux,iuz)
        case('gaussian-noise-x'); call gaunoise(ampluu(j),f,iux)
        case('gaussian-noise-y'); call gaunoise(ampluu(j),f,iuy)
        case('gaussian-noise-z'); call gaunoise(ampluu(j),f,iuz)
        case('gaussian-noise-xy'); call gaunoise(ampluu(j),f,iux,iuy)
        case('gaussian-noise-rprof')
          tmp=sqrt(xx**2+yy**2+zz**2)
          call gaunoise_rprof(ampluu(j),tmp,prof,f,iux,iuz)
        case('xjump')
          call jump(f,iux,uu_left,uu_right,widthuu,'x')
          call jump(f,iuy,uy_left,uy_right,widthuu,'x')
        case('Beltrami-x'); call beltrami(ampluu(j),f,iuu,kx=kx_uu)
        case('Beltrami-y'); call beltrami(ampluu(j),f,iuu,ky=ky_uu)
        case('Beltrami-z'); call beltrami(ampluu(j),f,iuu,kz=kz_uu)
        case('trilinear-x'); call trilinear(ampluu(j),f,iux,xx,yy,zz)
        case('trilinear-y'); call trilinear(ampluu(j),f,iuy,xx,yy,zz)
        case('trilinear-z'); call trilinear(ampluu(j),f,iuz,xx,yy,zz)
        case('cos-cos-sin-uz'); call cos_cos_sin(ampluu(j),f,iuz,xx,yy,zz)
        case('tor_pert'); call tor_pert(ampluu(j),f,iux,xx,yy,zz)
        case('diffrot'); call diffrot(ampluu(j),f,iuy,xx,yy,zz)
        case('olddiffrot'); call olddiffrot(ampluu(j),f,iuy,xx,yy,zz)
        case('sinwave-x'); call sinwave(ampluu(j),f,iux,kx=kx_uu)
        case('sinwave-y'); call sinwave(ampluu(j),f,iuy,ky=ky_uu)
        case('sinwave-z'); call sinwave(ampluu(j),f,iuz,kz=kz_uu)
        case('sinwave-ux-kx'); call sinwave(ampluu(j),f,iux,kx=kx_uu)
        case('sinwave-ux-ky'); call sinwave(ampluu(j),f,iux,ky=ky_uu)
        case('sinwave-ux-kz'); call sinwave(ampluu(j),f,iux,kz=kz_uu)
        case('sinwave-uy-kx'); call sinwave(ampluu(j),f,iuy,kx=kx_uu)
        case('sinwave-uy-ky'); call sinwave(ampluu(j),f,iuy,ky=ky_uu)
        case('sinwave-uy-kz'); call sinwave(ampluu(j),f,iuy,kz=kz_uu)
        case('sinwave-uz-kx'); call sinwave(ampluu(j),f,iuz,kx=kx_uu)
        case('sinwave-uz-ky'); call sinwave(ampluu(j),f,iuz,ky=ky_uu)
        case('sinwave-uz-kz'); call sinwave(ampluu(j),f,iuz,kz=kz_uu)
        case('sinwave-y-z')
          if (lroot) print*, 'init_uu: sinwave-y-z, ampluu=', ampluu(j)
          call sinwave(ampluu(j),f,iuy,kz=kz_uu)
        case('sinwave-z-y')
          if (lroot) print*, 'init_uu: sinwave-z-y, ampluu=', ampluu(j)
          call sinwave(ampluu(j),f,iuz,ky=ky_uu)
        case('sinwave-z-x')
          if (lroot) print*, 'init_uu: sinwave-z-x, ampluu=', ampluu(j)
          call sinwave(ampluu(j),f,iuz,kx=kx_uu)
        case('damped_sinwave-z-x')
          if (lroot) print*, 'init_uu: damped_sinwave-z-x, ampluu=', ampluu(j)
          do m=m1,m2; do n=n1,n2
            f(:,m,n,iuz)=f(:,m,n,iuz)+ampluu(j)*sin(kx_uu*x)*exp(-10*z(n)**2)
          enddo; enddo
        case('coswave-x'); call coswave(ampluu(j),f,iux,kx=kx_uu)
        case('coswave-y'); call coswave(ampluu(j),f,iuy,ky=ky_uu)
        case('coswave-z'); call coswave(ampluu(j),f,iuz,kz=kz_uu)
        case('coswave-x-z'); call coswave(ampluu(j),f,iux,kz=kz_uu)
        case('coswave-z-x'); call coswave(ampluu(j),f,iuz,kx=kx_uu)
        case('soundwave-x'); call soundwave(ampluu(j),f,iux,kx=kx_uu)
        case('soundwave-y'); call soundwave(ampluu(j),f,iuy,ky=ky_uu)
        case('soundwave-z'); call soundwave(ampluu(j),f,iuz,kz=kz_uu)
        case('robertsflow'); call robertsflow(ampluu(j),f,iuu)
        case('hawley-et-al'); call hawley_etal99a(ampluu(j),f,iuu,widthuu,Lxyz,xx,yy,zz)
        case('sound-wave', '11')
!
!  sound wave (should be consistent with density module)
!
          if (lroot) print*,'init_uu: x-wave in uu; ampluu(j)=',ampluu(j)
          f(:,:,:,iux)=uu_const(1)+ampluu(j)*sin(kx_uu*xx)

        case('sound-wave2')
!
!  sound wave (should be consistent with density module)
!
          crit=cs20-grav_const/kx_uu**2
          if (lroot) print*,'init_uu: x-wave in uu; crit,ampluu(j)=',crit,ampluu(j)
          if (crit>0.) then
            f(:,:,:,iux)=+ampluu(j)*cos(kx_uu*xx)*sqrt(abs(crit))
          else
            f(:,:,:,iux)=-ampluu(j)*sin(kx_uu*xx)*sqrt(abs(crit))
          endif

        case('shock-tube', '13')
!
!  shock tube test (should be consistent with density module)
!
          if (lroot) print*,'init_uu: polytopic standing shock'
          prof=.5*(1.+tanh(xx/widthuu))
          f(:,:,:,iux)=uu_left+(uu_right-uu_left)*prof

        case('shock-sphere')
!
!  shock tube test (should be consistent with density module)
!
          if (lroot) print*,'init_uu: spherical shock, widthuu=',widthuu,' radiusuu=',radiusuu
         ! where (sqrt(xx**2+yy**2+zz**2) .le. widthuu)
            f(:,:,:,iux)=0.5*xx/radiusuu*ampluu(j)*(1.-tanh((sqrt(xx**2+yy**2+zz**2)-radiusuu)/widthuu))
            f(:,:,:,iuy)=0.5*yy/radiusuu*ampluu(j)*(1.-tanh((sqrt(xx**2+yy**2+zz**2)-radiusuu)/widthuu))
            f(:,:,:,iuz)=0.5*zz/radiusuu*ampluu(j)*(1.-tanh((sqrt(xx**2+yy**2+zz**2)-radiusuu)/widthuu))
         !   f(:,:,:,iuy)=yy*ampluu(j)/(widthuu)
         !   f(:,:,:,iuz)=zz*ampluu(j)/(widthuu)
            !f(:,:,:,iux)=xx/sqrt(xx**2+yy**2+zz**2)*ampluu(j)
            !f(:,:,:,iuy)=yy/sqrt(xx**2+yy**2+zz**2)*ampluu(j)
            !f(:,:,:,iuz)=zz/sqrt(xx**2+yy**2+zz**2)*ampluu(j)
         ! endwhere
!

        case('bullets')
!
!  blob-like velocity perturbations (bullets)
!
          if (lroot) print*,'init_uu: velocity blobs'
          !f(:,:,:,iux)=f(:,:,:,iux)+ampluu(j)*exp(-(xx**2+yy**2+(zz-1.)**2)/widthuu)
          f(:,:,:,iuz)=f(:,:,:,iuz)-ampluu(j)*exp(-(xx**2+yy**2+zz**2)/widthuu)

        case('Alfven-circ-x')
!
!  circularly polarised Alfven wave in x direction
!
          if (lroot) print*,'init_uu: circular Alfven wave -> x'
          f(:,:,:,iuy) = f(:,:,:,iuy) + ampluu(j)*sin(kx_uu*xx)
          f(:,:,:,iuz) = f(:,:,:,iuz) + ampluu(j)*cos(kx_uu*xx)

        case('linear-shear')
!
!  Linear shear
!
          if (lroot) print*,'init_uu: linear-shear, ampluu=', ampluu(j)
          do l=l1,l2; do m=m1,m2
            f(l,m,n1:n2,iuy) = ampluu(j)*z(n1:n2)
          enddo; enddo
!
        case('tanh-x-z')
          if (lroot) print*, &
              'init_uu: tanh-x-z, widthuu, ampluu=', widthuu, ampluu(j)
          do l=l1,l2; do m=m1,m2
            f(l,m,n1:n2,iux) = ampluu(j)*tanh(z(n1:n2)/widthuu)
          enddo; enddo
!
        case('tanh-y-z')
          if (lroot) print*, &
              'init_uu: tanh-y-z, widthuu, ampluu=', widthuu, ampluu(j)
          do l=l1,l2; do m=m1,m2
            f(l,m,n1:n2,iuy) = ampluu(j)*tanh(z(n1:n2)/widthuu)
          enddo; enddo
!
        case('gauss-x-z')
          if (lroot) print*, &
              'init_uu: gauss-x-z, widthuu, ampluu=', widthuu, ampluu(j)
          do l=l1,l2; do m=m1,m2
            f(l,m,n1:n2,iux) = ampluu(j)*exp(-z(n1:n2)**2/widthuu**2)
          enddo; enddo
!
        case('const-ux')
!
!  constant x-velocity
!
          if (lroot) print*,'init_uu: constant x-velocity'
          f(:,:,:,iux) = ampluu(j)

        case('const-uy')
!
!  constant y-velocity
!
          if (lroot) print*,'init_uu: constant y-velocity'
          f(:,:,:,iuy) = ampluu(j)

        case('tang-discont-z')
!
!  tangential discontinuity: velocity is directed along x,
!  ux=uu_lower for z<0 and ux=uu_upper for z>0. This can
!  be set up together with 'rho-jump' in density.
!
          if (lroot) print*,'init_uu: tangential discontinuity of uux at z=0'
          if (lroot) print*,'init_uu: uu_lower=',uu_lower,' uu_upper=',uu_upper
          if (lroot) print*,'init_uu: widthuu=',widthuu
          prof=.5*(1.+tanh(zz/widthuu))
          f(:,:,:,iux)=uu_lower+(uu_upper-uu_lower)*prof

!  Add some random noise to see the development of instability
!WD: Can't we incorporate this into the urand stuff?
          print*, 'init_uu: ampluu(j)=',ampluu(j)
          call random_number_wrapper(r)
          call random_number_wrapper(p)
!          tmp=sqrt(-2*log(r))*sin(2*pi*p)*exp(-zz**2*10.)
          tmp=exp(-zz**2*10.)*cos(2.*xx+sin(4.*xx))
          f(:,:,:,iuz)=f(:,:,:,iuz)+ampluu(j)*tmp

        case('Fourier-trunc')
!
!  truncated simple Fourier series as nontrivial initial profile
!  for convection. The corresponding stream function is
!    exp(-(z-z1)^2/(2w^2))*(cos(kk)+2*sin(kk)+3*cos(3kk)),
!    with kk=k_x*x+k_y*y
!  Not a big success (convection starts much slower than with
!  random or 'up-down' ..
!
          if (lroot) print*,'init_uu: truncated Fourier'
          prof = ampluu(j)*exp(-0.5*(zz-z1)**2/widthuu**2) ! vertical Gaussian
          tmp = kx_uu*xx + ky_uu*yy               ! horizontal phase
          kabs = sqrt(kx_uu**2+ky_uu**2)
          f(:,:,:,iuz) = prof * kabs*(-sin(tmp) + 4*cos(2*tmp) - 9*sin(3*tmp))
          tmp = (zz-z1)/widthuu**2*prof*(cos(tmp) + 2*sin(2*tmp) + 3*cos(3*tmp))
          f(:,:,:,iux) = tmp*kx_uu/kabs
          f(:,:,:,iuy) = tmp*ky_uu/kabs
    
        case('up-down')
!
!  flow upwards in one spot, downwards in another; not soneloidal
! 
          if (lroot) print*,'init_uu: up-down'
          prof = ampluu(j)*exp(-0.5*(zz-z1)**2/widthuu**2) ! vertical profile
          tmp = sqrt((xx-(x0+0.3*Lx))**2+(yy-(y0+0.3*Ly))**2)! dist. from spot 1
          f(:,:,:,iuz) = prof*exp(-0.5*(tmp**2)/widthuu**2)
          tmp = sqrt((xx-(x0+0.5*Lx))**2+(yy-(y0+0.8*Ly))**2)! dist. from spot 1
          f(:,:,:,iuz) = f(:,:,:,iuz) - 0.7*prof*exp(-0.5*(tmp**2)/widthuu**2)

        case('powern') 
! initial spectrum k^power
          call powern(ampluu(j),initpower,cutoff,f,iux,iuz)

        case('power_randomphase') 
! initial spectrum k^power
          call power_randomphase(ampluu(j),initpower,cutoff,f,iux,iuz)
    
        case('random-isotropic-KS')
          call random_isotropic_KS(ampluu(j),initpower,cutoff,f,iux,iuz,N_modes_uu)

        case('vortex_2d')
! Vortex solution of Goodman, Narayan, & Goldreich (1987)
          call vortex_2d(f,xx,yy,b_ell,widthuu,rbound)

        case('sub-Keplerian')
          if (lroot) print*, 'init_hydro: set sub-Keplerian gas velocity'
          f(:,:,:,iux) = -1/(2*Omega)*1/gamma*cs20*beta_glnrho_scaled(2)
          f(:,:,:,iuy) = 1/(2*Omega)*1/gamma*cs20*beta_glnrho_scaled(1)
  
        case default
          !
          !  Catch unknown values
          !
          if (lroot) print*, 'init_uu: No such value for inituu: ', &
            trim(inituu(j))
          call stop_it("")
  
        endselect
!
!  End loop over initial conditions
!
      enddo
!
!  This allows an extra random velocity perturbation on
!  top of the initialization so far.
!
      if (urand /= 0) then
        if (lroot) print*, 'init_uu: Adding random uu fluctuations'
        if (urand > 0) then
          do i=iux,iuz
            call random_number_wrapper(tmp)
            f(:,:,:,i) = f(:,:,:,i) + urand*(tmp-0.5)
          enddo
        else
          if (lroot) print*, 'init_uu:  ... multiplicative fluctuations'
          do i=iux,iuz
            call random_number_wrapper(tmp)
            f(:,:,:,i) = f(:,:,:,i) * urand*(tmp-0.5)
          enddo
        endif
      endif
!
!     if (NO_WARN) print*,yy,zz !(keep compiler from complaining)
    endsubroutine init_uu
!***********************************************************************
    subroutine pencil_criteria_hydro()
!
!  All pencils that the Hydro module depends on are specified here.
!
!  20-11-04/anders: coded
!
      use Cdata
!      
      lpenc_requested(i_uu)=.true.
      lpenc_requested(i_ugu)=.true.
!
      if (lspecial) lpenc_requested(i_u2)=.true.
      if (dvid/=0.) then
        lpenc_video(i_oo)=.true.
        lpenc_video(i_o2)=.true.
        lpenc_video(i_u2)=.true.
      endif
!
      lpenc_diagnos(i_uu)=.true.
      if (idiag_oumphi/=0) lpenc_diagnos2d(i_ou)=.true.
      if (idiag_u2mphi/=0) lpenc_diagnos2d(i_u2)=.true.
      if (idiag_ox2m/=0 .or. idiag_oy2m/=0 .or. idiag_oz2m/=0 .or. &
          idiag_oxm /=0 .or. idiag_oym /=0 .or. idiag_ozm /=0 .or. &
          idiag_oxoym/=0 .or. idiag_oxozm/=0 .or. idiag_oyozm/=0) &
          lpenc_diagnos(i_oo)=.true.
      if (idiag_orms/=0 .or. idiag_omax/=0 .or. idiag_o2m/=0) &
          lpenc_diagnos(i_o2)=.true.
      if (idiag_oum/=0) lpenc_diagnos(i_ou)=.true.
      if (idiag_Marms/=0 .or. idiag_Mamax/=0) lpenc_diagnos(i_Ma2)=.true.
      if (idiag_u2u13m/=0) lpenc_diagnos(i_u2u13)=.true.
      if (idiag_urms/=0 .or. idiag_umax/=0 .or. idiag_rumax/=0 .or. &
          idiag_u2m/=0 .or. idiag_um2/=0) lpenc_diagnos(i_u2)=.true.
      if (idiag_duxdzma/=0 .or. idiag_duydzma/=0) lpenc_diagnos(i_uij)=.true.
      if (idiag_fmassz/=0) lpenc_diagnos(i_rho)=.true.
      if (idiag_ekin/=0 .or. idiag_ekintot/=0 .or. idiag_fkinz/=0 ) then
        lpenc_diagnos(i_rho)=.true.
        lpenc_diagnos(i_u2)=.true.
      endif
!
    endsubroutine pencil_criteria_hydro
!***********************************************************************
    subroutine pencil_interdep_hydro(lpencil_in)
!
!  Interdependency among pencils from the Hydro module is specified here.
!
!  20-11-04/anders: coded
!
      logical, dimension(npencils) :: lpencil_in
!
      if (lpencil_in(i_u2)) lpencil_in(i_uu)=.true.
      if (lpencil_in(i_divu)) lpencil_in(i_uij)=.true.
      if (lpencil_in(i_sij)) then
        lpencil_in(i_uij)=.true.
        lpencil_in(i_divu)=.true.
      endif
      if (lpencil_in(i_oo)) lpencil_in(i_uij)=.true.
      if (lpencil_in(i_o2)) lpencil_in(i_oo)=.true.
      if (lpencil_in(i_ou)) then
        lpencil_in(i_uu)=.true.
        lpencil_in(i_oo)=.true.
      endif
      if (lpencil_in(i_ugu)) then
        lpencil_in(i_uu)=.true.
        lpencil_in(i_uij)=.true.
      endif
      if (lpencil_in(i_u2u13)) then
        lpencil_in(i_uu)=.true.
        lpencil_in(i_uij)=.true.
      endif
!
    endsubroutine pencil_interdep_hydro
!***********************************************************************
    subroutine calc_pencils_hydro(f,p)
!
!  Calculate Hydro pencils.
!  Most basic pencils should come first, as others may depend on them.
!
!   08-nov-04/tony: coded
!
      use Cdata
      use Sub
!
      real, dimension (mx,my,mz,mvar+maux) :: f       
      type (pencil_case) :: p
!
      real, dimension (nx,3) :: gui
      real, dimension (nx) :: ugui
      integer :: i,j
!
      intent(in) :: f
      intent(inout) :: p
! uu
      if (lpencil(i_uu)) p%uu=f(l1:l2,m,n,iux:iuz)
! u2
      if (lpencil(i_u2)) then
        call dot2_mn(p%uu,p%u2)
      endif
! uij
      if (lpencil(i_uij)) call gij(f,iuu,p%uij,1)
! divu
      if (lpencil(i_divu)) call div_mn(p%uij,p%divu,p%uu)
! sij
      if (lpencil(i_sij)) then
        do j=1,3
          do i=1,3
            p%sij(:,i,j)=.5*(p%uij(:,i,j)+p%uij(:,j,i))
          enddo
          p%sij(:,j,j)=p%sij(:,j,j)-(1./3.)*p%divu
        enddo
      endif
! sij2
      if (lpencil(i_sij2)) call multm2_mn(p%sij,p%sij2)
! uij5
      if (lpencil(i_uij5)) call gij(f,iuu,p%uij5,5)
! oo
      if (lpencil(i_oo)) then
        p%oo(:,1)=p%uij(:,3,2)-p%uij(:,2,3)
        p%oo(:,2)=p%uij(:,1,3)-p%uij(:,3,1)
        p%oo(:,3)=p%uij(:,2,1)-p%uij(:,1,2)
      endif
! o2
      if (lpencil(i_o2)) call dot2_mn(p%oo,p%o2)
! ou
      if (lpencil(i_ou)) call dot_mn(p%oo,p%uu,p%ou)
! ugu
      if (lpencil(i_ugu)) then
        if (.not. lupw_uu) then
          call multmv_mn(p%uij,p%uu,p%ugu)
        else ! upwinding of velocity -- experimental and inefficent
          if (headtt) print*, &
              'calc_pencils_hydro: upwinding advection term; use at own risk!'
!
          call grad(f,iux,gui)    ! gu=grad ux
          call u_dot_gradf(f,iux,gui,p%uu,ugui,UPWIND=lupw_uu)
          p%ugu(:,1) = ugui
!
          call grad(f,iuy,gui)    ! gu=grad ux
          call u_dot_gradf(f,iuy,gui,p%uu,ugui,UPWIND=lupw_uu)
          p%ugu(:,2) = ugui
!
          call grad(f,iuz,gui)    ! gu=grad ux
          call u_dot_gradf(f,iuz,gui,p%uu,ugui,UPWIND=lupw_uu)
          p%ugu(:,3) = ugui
        endif
      endif
! u2u13
      if (lpencil(i_u2u13)) p%u2u13=p%uu(:,2)*p%uij(:,1,3)
! del2u
! del6u
      if (lpencil(i_del6u)) call del6v(f,iuu,p%del6u)
! graddivu
      if (lpencil(i_del2u)) then 
        if (lpencil(i_graddivu)) then 
          call del2v_etc(f,iuu,p%del2u,GRADDIV=p%graddivu)
        else
          call del2v(f,iuu,p%del2u)
        endif
      else
        if (lpencil(i_graddivu)) call del2v_etc(f,iuu,GRADDIV=p%graddivu)
      endif
!
    endsubroutine calc_pencils_hydro
!***********************************************************************
    subroutine duu_dt(f,df,p)
!
!  velocity evolution
!  calculate du/dt = - u.gradu - 2Omega x u + grav + Fvisc
!  pressure gradient force added in density and entropy modules.
!
!   7-jun-02/axel: incoporated from subroutine pde
!  10-jun-02/axel+mattias: added Coriolis force
!  23-jun-02/axel: glnrho and fvisc are now calculated in here
!  17-jun-03/ulf:  ux2, uy2 and uz2 added as diagnostic quantities
!
      use Cdata
      use Sub
      use IO
      use Slices,  only: divu_yz, divu_xy, divu_xy2, divu_xz, &
                         oo_xy, oo_xy2, oo_xz, oo_yz, &
                         o2_xy, o2_xy2, o2_xz, o2_yz, &
                         u2_xy, u2_xy2, u2_xz, u2_yz
      use Mpicomm, only: stop_it
      use Special, only: special_calc_hydro
!ajwm QUICK FIX.... Shouldn't be here!
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz,mvar) :: df
      type (pencil_case) :: p
!      
      real, dimension (nx) :: pdamp
      real :: c2,s2
      integer :: i,j
!
      intent(in) :: f,p
      intent(out) :: df
!
!  identify module and boundary conditions
!
      if (headtt.or.ldebug) print*,'duu_dt: SOLVE'
      if (headtt) then
        call identify_bcs('ux',iux)
        call identify_bcs('uy',iuy)
        call identify_bcs('uz',iuz)
      endif
!
!  advection term
!
      df(l1:l2,m,n,iux:iuz) = df(l1:l2,m,n,iux:iuz) - p%ugu
!
!  Coriolis force, -2*Omega x u
!  Omega=(-sin_theta, 0, cos_theta)
!  theta corresponds to latitude, but to have the box located on the
!  right hand side of the sphere (grav still pointing dowward and then
!  Omega to the left), one should choose Omega=-90 for the equator,
!  for example.
!
      if (Omega/=0.) then
        if (theta==0) then
          if (headtt) print*,'duu_dt: add Coriolis force; Omega=',Omega
          c2=2*Omega
          df(l1:l2,m,n,iux)=df(l1:l2,m,n,iux)+c2*p%uu(:,2)
          df(l1:l2,m,n,iuy)=df(l1:l2,m,n,iuy)-c2*p%uu(:,1)
          !
          !  add centrifugal force (doing this with periodic boundary
          !  conditions in x and y would not be compatible, so it is
          !  therefore usually ignored in those cases!)
          !
          if (lcentrifugal_force) then
            if (headtt) print*,'duu_dt: add Centrifugal force; Omega=',Omega
            df(l1:l2,m,n,iux)=df(l1:l2,m,n,iux)+x(l1:l2)*Omega**2
            df(l1:l2,m,n,iuy)=df(l1:l2,m,n,iuy)+y(  m  )*Omega**2
          endif
        else
          !
          !  add Coriolis force with an angle (defined such that theta=-60,
          !  for example, would correspond to 30 degrees latitude).
          !  Omega=(sin(theta), 0, cos(theta)).
          !
          if (headtt) print*,'duu_dt: Coriolis force; Omega,theta=',Omega,theta
          c2=2*Omega*cos(theta*pi/180.)
          s2=2*Omega*sin(theta*pi/180.)
          df(l1:l2,m,n,iux)=df(l1:l2,m,n,iux)+c2*p%uu(:,2)
          df(l1:l2,m,n,iuy)=df(l1:l2,m,n,iuy)-c2*p%uu(:,1)+s2*p%uu(:,3)
          df(l1:l2,m,n,iuz)=df(l1:l2,m,n,iuz)             -s2*p%uu(:,2)
        endif
      endif
!
! calculate viscous force
!
      if (lviscosity) call calc_viscous_force(f,df,p)
!
!  ``uu/dx'' for timestep
!
      if (lfirst.and.ldt) advec_uu=abs(p%uu(:,1))*dx_1(l1:l2)+ &
                                   abs(p%uu(:,2))*dy_1(  m  )+ &
                                   abs(p%uu(:,3))*dz_1(  n  )
      if (headtt.or.ldebug) print*,'duu_dt: max(advec_uu) =',maxval(advec_uu)
!
!  damp motions in some regions for some time spans if desired
!
! geodynamo
! addition of dampuint evaluation
      if (tdamp/=0.or.dampuext/=0.or.dampuint/=0) call udamping(f,df)
! end geodynamo
!
!  adding differential rotation via a frictional term
!  (should later be moved to a separate routine)
!  15-aug-03/christer: Added amplitude (ampl_diffrot) below
!   7-jun-03/axel: modified to turn off diffrot for x>0 (recycle use of rdampint)
!
      if (tau_diffrot1/=0) then
        if (wdamp/=0.) then
          pdamp=1.-step(x_mn,rdampint,wdamp) ! outer damping profile
        else
          pdamp=1.
        endif
        df(l1:l2,m,n,iuy)=df(l1:l2,m,n,iuy)-tau_diffrot1* &
                          (f(l1:l2,m,n,iuy)-ampl_diffrot*&
                          cos(kx_diffrot*x(l1:l2))**xexp_diffrot* &
                          cos(z(n))*pdamp)
      endif
!
!  add the possibility of removing a mean flow in the y-direction
!
      if (tau_damp_ruxm/=0.) call damp_ruxm(f,df,p%rho)
      if (tau_damp_ruym/=0.) call damp_ruym(f,df,p%rho)
!
!  interface for your personal subroutines calls
!
      if (lspecial) call special_calc_hydro(f,df,p%uu,p%glnrho,p%divu,p%rho1,p%u2,p%uij)
!
!  write slices for output in wvid in run.f90
!  This must be done outside the diagnostics loop (accessed at different times).
!  Note: ix is the index with respect to array with ghost zones.
!
      if(lvid.and.lfirst) then
        divu_yz(m-m1+1,n-n1+1)=p%divu(ix-l1+1)
        if (m.eq.iy)  divu_xz(:,n-n1+1)=p%divu
        if (n.eq.iz)  divu_xy(:,m-m1+1)=p%divu
        if (n.eq.iz2) divu_xy2(:,m-m1+1)=p%divu
        do j=1,3
          oo_yz(m-m1+1,n-n1+1,j)=p%oo(ix-l1+1,j)
          if (m==iy)  oo_xz(:,n-n1+1,j)=p%oo(:,j)
          if (n==iz)  oo_xy(:,m-m1+1,j)=p%oo(:,j)
          if (n==iz2) oo_xy2(:,m-m1+1,j)=p%oo(:,j)
        enddo
        u2_yz(m-m1+1,n-n1+1)=p%u2(ix-l1+1)
        if (m==iy)  u2_xz(:,n-n1+1)=p%u2
        if (n==iz)  u2_xy(:,m-m1+1)=p%u2
        if (n==iz2) u2_xy2(:,m-m1+1)=p%u2
        o2_yz(m-m1+1,n-n1+1)=p%o2(ix-l1+1)
        if (m==iy)  o2_xz(:,n-n1+1)=p%o2
        if (n==iz)  o2_xy(:,m-m1+1)=p%o2
        if (n==iz2) o2_xy2(:,m-m1+1)=p%o2
        if(othresh_per_orms/=0) call calc_othresh
        call vecout(41,trim(directory)//'/ovec',p%oo,othresh,novec)
      endif
!
!  Calculate maxima and rms values for diagnostic purposes
!
      if (ldiagnos) then
        if (headtt.or.ldebug) print*,'duu_dt: Calculate maxima and rms values...'
        if (idiag_dtu/=0) call max_mn_name(advec_uu/cdt,idiag_dtu,l_dt=.true.)
        if (idiag_urms/=0)   call sum_mn_name(p%u2,idiag_urms,lsqrt=.true.)
        if (idiag_umax/=0)   call max_mn_name(p%u2,idiag_umax,lsqrt=.true.)
        if (idiag_uzrms/=0) &
            call sum_mn_name(p%uu(:,3)**2,idiag_uzrms,lsqrt=.true.)
        if (idiag_uzmax/=0) &
            call max_mn_name(p%uu(:,3)**2,idiag_uzmax,lsqrt=.true.)
        if (idiag_rumax/=0) call max_mn_name(p%u2*p%rho**2,idiag_rumax,lsqrt=.true.)
        if (idiag_u2m/=0)     call sum_mn_name(p%u2,idiag_u2m)
        if (idiag_um2/=0)     call max_mn_name(p%u2,idiag_um2)
        if (idiag_divum/=0)   call sum_mn_name(p%divu,idiag_divum)
        if (idiag_divu2m/=0)  call sum_mn_name(p%divu**2,idiag_divu2m)
        if (idiag_ux2m/=0)    call sum_mn_name(p%uu(:,1)**2,idiag_ux2m)
        if (idiag_uy2m/=0)    call sum_mn_name(p%uu(:,2)**2,idiag_uy2m)
        if (idiag_uz2m/=0)    call sum_mn_name(p%uu(:,3)**2,idiag_uz2m)
        if (idiag_uxuym/=0)   call sum_mn_name(p%uu(:,1)*p%uu(:,2),idiag_uxuym)
        if (idiag_uxuzm/=0)   call sum_mn_name(p%uu(:,1)*p%uu(:,3),idiag_uxuzm)
        if (idiag_uyuzm/=0)   call sum_mn_name(p%uu(:,2)*p%uu(:,3),idiag_uyuzm)
        if (idiag_uxuymz/=0)  call xysum_mn_name_z(p%uu(:,1)*p%uu(:,2),idiag_uxuymz)
        if (idiag_uxuzmz/=0)  call xysum_mn_name_z(p%uu(:,1)*p%uu(:,3),idiag_uxuzmz)
        if (idiag_uyuzmz/=0)  call xysum_mn_name_z(p%uu(:,2)*p%uu(:,3),idiag_uyuzmz)
        if (idiag_duxdzma/=0) call sum_mn_name(abs(p%uij(:,1,3)),idiag_duxdzma)
        if (idiag_duydzma/=0) call sum_mn_name(abs(p%uij(:,2,3)),idiag_duydzma)
!
        if (idiag_ekin/=0)  call sum_mn_name(.5*p%rho*p%u2,idiag_ekin)
        if (idiag_ekintot/=0) & 
            call integrate_mn_name(.5*p%rho*p%u2,idiag_ekintot)
!
!  kinetic field components at one point (=pt)
!
        if (lroot.and.m==mpoint.and.n==npoint) then
          if (idiag_uxpt/=0) call save_name(p%uu(lpoint-nghost,1),idiag_uxpt)
          if (idiag_uypt/=0) call save_name(p%uu(lpoint-nghost,2),idiag_uypt)
          if (idiag_uzpt/=0) call save_name(p%uu(lpoint-nghost,3),idiag_uzpt)
        endif
!
!  this doesn't need to be as frequent (check later)
!
        if (idiag_fmassz/=0) call xysum_mn_name_z(p%rho*p%uu(:,3),idiag_fmassz)
        if (idiag_fkinz/=0) call xysum_mn_name_z(.5*p%rho*p%u2*p%uu(:,3),idiag_fkinz)
        if (idiag_uxmz/=0) call xysum_mn_name_z(p%uu(:,1),idiag_uxmz)
        if (idiag_uymz/=0) call xysum_mn_name_z(p%uu(:,2),idiag_uymz)
        if (idiag_uzmz/=0) call xysum_mn_name_z(p%uu(:,3),idiag_uzmz)
        if (idiag_uxmxy/=0) call zsum_mn_name_xy(p%uu(:,1),idiag_uxmxy)
        if (idiag_uymxy/=0) call zsum_mn_name_xy(p%uu(:,2),idiag_uymxy)
        if (idiag_uzmxy/=0) call zsum_mn_name_xy(p%uu(:,3),idiag_uzmxy)
!
!  mean momenta
!
        if (idiag_ruxm/=0) call sum_mn_name(p%rho*p%uu(:,1),idiag_ruxm)
        if (idiag_ruym/=0) call sum_mn_name(p%rho*p%uu(:,2),idiag_ruym)
        if (idiag_ruzm/=0) call sum_mn_name(p%rho*p%uu(:,3),idiag_ruzm)
!
!  things related to vorticity
!
!
        if (idiag_oum/=0) call sum_mn_name(p%ou,idiag_oum)
        if(idiag_orms/=0) call sum_mn_name(p%o2,idiag_orms,lsqrt=.true.)
        if(idiag_omax/=0) call max_mn_name(p%o2,idiag_omax,lsqrt=.true.)
        if(idiag_o2m/=0)  call sum_mn_name(p%o2,idiag_o2m)
        if (idiag_ox2m/=0) call sum_mn_name(p%oo(:,1)**2,idiag_ox2m)
        if (idiag_oy2m/=0) call sum_mn_name(p%oo(:,2)**2,idiag_oy2m)
        if (idiag_oz2m/=0) call sum_mn_name(p%oo(:,3)**2,idiag_oz2m)
        if (idiag_oxm /=0) call sum_mn_name(p%oo(:,1)   ,idiag_oxm)
        if (idiag_oym /=0) call sum_mn_name(p%oo(:,2)   ,idiag_oym)
        if (idiag_ozm /=0) call sum_mn_name(p%oo(:,3)   ,idiag_ozm)
        if (idiag_oxoym/=0) call sum_mn_name(p%oo(:,1)*p%oo(:,2),idiag_oxoym)
        if (idiag_oxozm/=0) call sum_mn_name(p%oo(:,1)*p%oo(:,3),idiag_oxozm)
        if (idiag_oyozm/=0) call sum_mn_name(p%oo(:,2)*p%oo(:,3),idiag_oyozm)
!
!  Mach number, rms and max
!
        if (idiag_Marms/=0) call sum_mn_name(p%Ma2,idiag_Marms,lsqrt=.true.)
        if (idiag_Mamax/=0) call max_mn_name(p%Ma2,idiag_Mamax,lsqrt=.true.)
!
!  < u2 u1,3 >
!
        if (idiag_u2u13m/=0) call sum_mn_name(p%u2u13,idiag_u2u13m)
!
      endif
!
!  phi-averages
!  Note that this does not necessarily happen with ldiagnos=.true.
!
      if (l2davgfirst) then
        call phisum_mn_name_rz(p%uu(:,1)*pomx+p%uu(:,2)*pomy,idiag_urmphi)
        call phisum_mn_name_rz(p%uu(:,1)*phix+p%uu(:,2)*phiy,idiag_upmphi)
        call phisum_mn_name_rz(p%uu(:,3),idiag_uzmphi)
        call phisum_mn_name_rz(p%u2,idiag_u2mphi)
        if (idiag_oumphi/=0) call phisum_mn_name_rz(p%ou,idiag_oumphi)
      endif
!
    endsubroutine duu_dt
!***********************************************************************
    subroutine calc_othresh()
!
!  calculate othresh from orms, give warnings if there are problems
!
!  24-nov-03/axel: adapted from calc_bthresh
!
      use Cdata
!
!  give warning if orms is not set in prints.in
!
      if(idiag_orms==0) then
        if(lroot.and.lfirstpoint) then
          print*,'calc_othresh: need to set orms in print.in to get othresh'
        endif
      endif
!
!  if nvec exceeds novecmax (=1/4) of points per processor, then begin to
!  increase scaling factor on othresh. These settings will stay in place
!  until the next restart
!
      if(novec>novecmax.and.lfirstpoint) then
        print*,'calc_othresh: processor ',iproc,': othresh_scl,novec,novecmax=', &
                                                   othresh_scl,novec,novecmax
        othresh_scl=othresh_scl*1.2
      endif
!
!  calculate othresh as a certain fraction of orms
!
      othresh=othresh_scl*othresh_per_orms*orms
!
    endsubroutine calc_othresh
!***********************************************************************
    subroutine damp_ruxm(f,df,rho)
!
!  Damps mean x momentum, ruxm, to zero.
!  This can be useful in situations where a mean flow is generated.
!  This tends to be the case when there is linear shear but no rotation
!  and the turbulence is forced. A constant drift velocity in the
!  x-direction is most dangerous, because it leads to a linear increase
!  of <uy> due to the shear term. If there is rotation, the epicyclic
!  motion brings one always back to no mean flow on the average.
!
!  20-aug-02/axel: adapted from damp_ruym
!   7-sep-02/axel: corrected mpireduce_sum (was mpireduce_max)
!   1-oct-02/axel: turned into correction of momentum rather than velocity
!
      use Cdata
      use Mpicomm
      use Sub
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz,mvar) :: df
      real, dimension(nx) :: rho,ux
      real, dimension(1) :: fsum_tmp,fsum
      real :: tau_damp_ruxm1
      real, save :: ruxm=0.,rux_sum=0.
!
!  at the beginning of each timestep we calculate ruxm
!  using the sum of rho*ux over all meshpoints, rux_sum,
!  that was calculated at the end of the previous step.
!  This result is only known on the root processor and
!  needs to be broadcasted.
!
      if(lfirstpoint) then
        fsum_tmp(1)=rux_sum
        call mpireduce_sum(fsum_tmp,fsum,1)
        if(lroot) ruxm=fsum(1)/(nw*ncpus)
        call mpibcast_real(ruxm,1)
      endif
!
      ux=f(l1:l2,m,n,iux)
      call sum_mn(rho*ux,rux_sum)
      tau_damp_ruxm1=1./tau_damp_ruxm
      df(l1:l2,m,n,iux)=df(l1:l2,m,n,iux)-tau_damp_ruxm1*ruxm/rho
!
    endsubroutine damp_ruxm
!***********************************************************************
    subroutine damp_ruym(f,df,rho)
!
!  Damps mean y momentum, ruym, to zero.
!  This can be useful in situations where a mean flow is generated.
!
!  18-aug-02/axel: coded
!   1-oct-02/axel: turned into correction of momentum rather than velocity
!
      use Cdata
      use Mpicomm
      use Sub
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz,mvar) :: df
      real, dimension(nx) :: rho,uy
      real, dimension(1) :: fsum_tmp,fsum
      real :: tau_damp_ruym1
      real, save :: ruym=0.,ruy_sum=0.
!
!  at the beginning of each timestep we calculate ruym
!  using the sum of rho*uy over all meshpoints, ruy_sum,
!  that was calculated at the end of the previous step.
!  This result is only known on the root processor and
!  needs to be broadcasted.
!
      if(lfirstpoint) then
        fsum_tmp(1)=ruy_sum
        call mpireduce_sum(fsum_tmp,fsum,1)
        if(lroot) ruym=fsum(1)/(nw*ncpus)
        call mpibcast_real(ruym,1)
      endif
!
      uy=f(l1:l2,m,n,iuy)
      call sum_mn(rho*uy,ruy_sum)
      tau_damp_ruym1=1./tau_damp_ruym
      df(l1:l2,m,n,iuy)=df(l1:l2,m,n,iuy)-tau_damp_ruym1*ruym/rho
!
    endsubroutine damp_ruym
! !***********************************************************************
!     function step(x,x0,width)
! !
! !  Smooth unit step function centred at x0; implemented as tanh profile
! !  23-jan-02/wolf: coded
! !  09-feb-05/tony: copied here to prevent compiler error with intel 7.1
! !
!       use Cdata, only: epsi
! !
!       real, dimension(:) :: x
!       real, dimension(size(x,1)) :: step
!       real :: x0,width

!         step = 0.5*(1+tanh((x-x0)/(width+epsi)))
! !
!       endfunction step
!***********************************************************************
    subroutine udamping(f,df)
!
!  damping terms (artificial, but sometimes useful):
!
!  20-nov-04/axel: added cylindrical Couette flow
!
      use Cdata
      use Mpicomm, only: stop_it
      use Sub, only: step,sum_mn_name
!
      real, dimension (mx,my,mz,mvar+maux) :: f
      real, dimension (mx,my,mz,mvar) :: df
!
      real, dimension(nx) :: pdamp,fint_work,fext_work
      real, dimension(nx,3) :: fint,fext
      real :: zbot,ztop,t_infl,t_span,tau,pfade
      integer :: i,j
!  
!  warn about the damping term
!
        if (headtt .and. (dampu /= 0.) .and. (t < tdamp)) then
          if (ldamp_fade) then
            print*, 'udamping: Damping velocities constantly until time ', tdamp
          else
            print*, 'udamping: Damping velocities smoothly until time ', tdamp
          end if
        endif
!
!  define bottom and top height
!
      zbot=xyz0(3)
      ztop=xyz0(3)+Lxyz(3)
!
!  1. damp motion during time interval 0<t<tdamp.
!  Damping coefficient is dampu (if >0) or |dampu|/dt (if dampu <0).
!  With ldamp_fade=T, damping coefficient is smoothly fading out
!

        if ((dampu .ne. 0.) .and. (t < tdamp)) then
          if (ldamp_fade) then  ! smoothly fade
            !
            ! smoothly fade out damping according to the following
            ! function of time:
            !
            !    ^
            !    |
            !  1 +**************
            !    |              ****
            !    |                  **
            !    |                    *
            !    |                     **
            !    |                       ****
            !  0 +-------------+-------------**********---> t
            !    |             |             |
            !    0          Tdamp/2        Tdamp
            !
            ! i.e. for 0<t<Tdamp/2, full damping is applied, while for
            ! Tdamp/2<t<Tdamp, damping goes smoothly (with continuous
            ! derivatives) to zero.
            !
            t_infl = 0.75*tdamp ! position of inflection point
            t_span = 0.5*tdamp   ! width of transition (1->0) region
            tau = (t-t_infl)/t_span ! normalized t, tr. region is [-0.5,0.5]
            if (tau <= -0.5) then
              pfade = 1.
            elseif (tau <= 0.5) then
              pfade = 0.5*(1-tau*(3-4*tau**2))
            else
              call stop_it("UDAMPING: Never got here.")
            endif
          else                ! don't fade, switch
            pfade = 1.
          endif
          !
          ! damp absolutely or relative to time step
          !
          if (dampu > 0) then   ! absolutely
            df(l1:l2,m,n,iux:iuz) = df(l1:l2,m,n,iux:iuz) &
                                    - pfade*dampu*f(l1:l2,m,n,iux:iuz)
          else                  ! relative to dt
            if (dt > 0) then    ! dt known and good
              df(l1:l2,m,n,iux:iuz) = df(l1:l2,m,n,iux:iuz) &
                                      + pfade*dampu/dt*f(l1:l2,m,n,iux:iuz)
            else
              call stop_it("UDAMP: dt <=0 -- what does this mean?")
            endif
          endif
        endif
!
!  2. damp motions for r_mn > rdampext or r_ext AND r_mn < rdampint or r_int
!
        if (lgravr) then        ! why lgravr here? to ensure we know r_mn??
! geodynamo
! original block
!          pdamp = step(r_mn,rdamp,wdamp) ! damping profile
!          do i=iux,iuz
!            df(l1:l2,m,n,i) = df(l1:l2,m,n,i) - dampuext*pdamp*f(l1:l2,m,n,i)
!          enddo
!
          if (dampuext > 0.0 .and. rdampext /= impossible) then
            pdamp = step(r_mn,rdampext,wdamp) ! outer damping profile
            do i=iux,iuz
              df(l1:l2,m,n,i) = df(l1:l2,m,n,i) - dampuext*pdamp*f(l1:l2,m,n,i)
            enddo
          endif

          if (dampuint > 0.0) then
            pdamp = 1 - step(r_mn,rdampint,wdamp) ! inner damping profile
            do i=iux,iuz
              df(l1:l2,m,n,i) = df(l1:l2,m,n,i) - dampuint*pdamp*f(l1:l2,m,n,i)
            enddo
          endif
! end geodynamo 
        endif
!
!  coupling the above internal and external rotation rates to lgravr is not
!  a good idea. So, because of that, spherical Couette flow has to be coded
!  separately.
!  ==> reconsider name <==
!  Allow now also for cylindical Couette flow (if lcylindrical=T)
!
        if (lOmega_int) then
!
!  relax outer angular velocity to zero, and
!  calculate work done to sustain zero rotation on outer cylinder/sphere
!
!
          if (lcylindrical) then
            pdamp = step(rcyl_mn,rdampext,wdamp) ! outer damping profile
          else
            pdamp = step(r_mn,rdampext,wdamp) ! outer damping profile
          endif
          do i=1,3
            j=iux-1+i
            fext(:,i)=-dampuext*pdamp*f(l1:l2,m,n,j)
            df(l1:l2,m,n,j)=df(l1:l2,m,n,j)+fext(:,i)
          enddo
          if (idiag_fextm/=0) then
            fext_work=f(l1:l2,m,n,iux)*fext(:,1)&
                     +f(l1:l2,m,n,iuy)*fext(:,2)&
                     +f(l1:l2,m,n,iuz)*fext(:,3)
            call sum_mn_name(fext_work,idiag_fextm)
          endif
!
!  internal angular velocity, uref=(-y,x,0)*Omega_int, and
!  calculate work done to sustain uniform rotation on inner cylinder/sphere
!
          if (dampuint > 0.0) then
            if (lcylindrical) then
              pdamp = 1 - step(rcyl_mn,rdampint,wdamp) ! inner damping profile
            else
              pdamp = 1 - step(r_mn,rdampint,wdamp) ! inner damping profile
            endif
            fint(:,1)=-dampuint*pdamp*(f(l1:l2,m,n,iux)+y(m)*Omega_int)
            fint(:,2)=-dampuint*pdamp*(f(l1:l2,m,n,iuy)-x(l1:l2)*Omega_int)
            fint(:,3)=-dampuint*pdamp*(f(l1:l2,m,n,iuz))
            df(l1:l2,m,n,iux)=df(l1:l2,m,n,iux)+fint(:,1)
            df(l1:l2,m,n,iuy)=df(l1:l2,m,n,iuy)+fint(:,2)
            df(l1:l2,m,n,iuz)=df(l1:l2,m,n,iuz)+fint(:,3)
            if (idiag_fintm/=0) then
              fint_work=f(l1:l2,m,n,iux)*fint(:,1)&
                       +f(l1:l2,m,n,iuy)*fint(:,2)&
                       +f(l1:l2,m,n,iuz)*fint(:,3)
              call sum_mn_name(fint_work,idiag_fintm)
            endif
          endif
        endif
!
    endsubroutine udamping
!***********************************************************************
    subroutine rprint_hydro(lreset,lwrite)
!
!  reads and registers print parameters relevant for hydro part
!
!   3-may-02/axel: coded
!  27-may-02/axel: added possibility to reset list
!
      use Cdata
      use Sub
!
      integer :: iname,inamez,ixy,irz
      logical :: lreset,lwr
      logical, optional :: lwrite
!
      lwr = .false.
      if (present(lwrite)) lwr=lwrite
!
!  reset everything in case of reset
!  (this needs to be consistent with what is defined above!)
!
      if (lreset) then
        idiag_u2m=0; idiag_um2=0; idiag_oum=0; idiag_o2m=0
        idiag_uxpt=0; idiag_uypt=0; idiag_uzpt=0; idiag_dtu=0
        idiag_dtv=0; idiag_urms=0; idiag_umax=0; idiag_uzrms=0; idiag_uzmax=0
        idiag_orms=0; idiag_omax=0
        idiag_ruxm=0; idiag_ruym=0; idiag_ruzm=0; idiag_rumax=0
        idiag_ux2m=0; idiag_uy2m=0; idiag_uz2m=0
        idiag_uxuym=0; idiag_uxuzm=0; idiag_uyuzm=0
        idiag_uxuymz=0; idiag_uxuzmz=0; idiag_uyuzmz=0
        idiag_ox2m=0; idiag_oy2m=0; idiag_oz2m=0; idiag_oxm=0; idiag_oym=0
        idiag_ozm=0; idiag_oxoym=0; idiag_oxozm=0; idiag_oyozm=0
        idiag_umx=0; idiag_umy=0; idiag_umz=0
        idiag_Marms=0; idiag_Mamax=0; idiag_divum=0; idiag_divu2m=0
        idiag_u2u13m=0; idiag_oumphi=0; idiag_fintm=0; idiag_fextm=0
        idiag_urmphi=0; idiag_upmphi=0; idiag_uzmphi=0; idiag_u2mphi=0
        idiag_duxdzma=0; idiag_duydzma=0
        idiag_ekin=0; idiag_ekintot=0
        idiag_fmassz=0; idiag_fkinz=0
      endif
!
!  iname runs through all possible names that may be listed in print.in
!
      if(lroot.and.ip<14) print*,'run through parse list'
      do iname=1,nname
        call parse_name(iname,cname(iname),cform(iname),'ekin',idiag_ekin)
        call parse_name(iname,cname(iname),cform(iname),'ekintot',idiag_ekintot)
        call parse_name(iname,cname(iname),cform(iname),'u2m',idiag_u2m)
        call parse_name(iname,cname(iname),cform(iname),'um2',idiag_um2)
        call parse_name(iname,cname(iname),cform(iname),'o2m',idiag_o2m)
        call parse_name(iname,cname(iname),cform(iname),'oum',idiag_oum)
        call parse_name(iname,cname(iname),cform(iname),'dtu',idiag_dtu)
        call parse_name(iname,cname(iname),cform(iname),'dtv',idiag_dtv)
        call parse_name(iname,cname(iname),cform(iname),'urms',idiag_urms)
        call parse_name(iname,cname(iname),cform(iname),'umax',idiag_umax)
        call parse_name(iname,cname(iname),cform(iname),'uzrms',idiag_uzrms)
        call parse_name(iname,cname(iname),cform(iname),'uzmax',idiag_uzmax)
        call parse_name(iname,cname(iname),cform(iname),'ux2m',idiag_ux2m)
        call parse_name(iname,cname(iname),cform(iname),'uy2m',idiag_uy2m)
        call parse_name(iname,cname(iname),cform(iname),'uz2m',idiag_uz2m)
        call parse_name(iname,cname(iname),cform(iname),'uxuym',idiag_uxuym)
        call parse_name(iname,cname(iname),cform(iname),'uxuzm',idiag_uxuzm)
        call parse_name(iname,cname(iname),cform(iname),'uyuzm',idiag_uyuzm)
        call parse_name(iname,cname(iname),cform(iname),'ox2m',idiag_ox2m)
        call parse_name(iname,cname(iname),cform(iname),'oy2m',idiag_oy2m)
        call parse_name(iname,cname(iname),cform(iname),'oz2m',idiag_oz2m)
        call parse_name(iname,cname(iname),cform(iname),'oxm',idiag_oxm)
        call parse_name(iname,cname(iname),cform(iname),'oym',idiag_oym)
        call parse_name(iname,cname(iname),cform(iname),'ozm',idiag_ozm)
        call parse_name(iname,cname(iname),cform(iname),'oxoym',idiag_oxoym)
        call parse_name(iname,cname(iname),cform(iname),'oxozm',idiag_oxozm)
        call parse_name(iname,cname(iname),cform(iname),'oyozm',idiag_oyozm)
        call parse_name(iname,cname(iname),cform(iname),'orms',idiag_orms)
        call parse_name(iname,cname(iname),cform(iname),'omax',idiag_omax)
        call parse_name(iname,cname(iname),cform(iname),'ruxm',idiag_ruxm)
        call parse_name(iname,cname(iname),cform(iname),'ruym',idiag_ruym)
        call parse_name(iname,cname(iname),cform(iname),'ruzm',idiag_ruzm)
        call parse_name(iname,cname(iname),cform(iname),'rumax',idiag_rumax)
        call parse_name(iname,cname(iname),cform(iname),'umx',idiag_umx)
        call parse_name(iname,cname(iname),cform(iname),'umy',idiag_umy)
        call parse_name(iname,cname(iname),cform(iname),'umz',idiag_umz)
        call parse_name(iname,cname(iname),cform(iname),'Marms',idiag_Marms)
        call parse_name(iname,cname(iname),cform(iname),'Mamax',idiag_Mamax)
        call parse_name(iname,cname(iname),cform(iname),'divum',idiag_divum)
        call parse_name(iname,cname(iname),cform(iname),'divu2m',idiag_divu2m)
        call parse_name(iname,cname(iname),cform(iname),'u2u13m',idiag_u2u13m)
        call parse_name(iname,cname(iname),cform(iname),'uxpt',idiag_uxpt)
        call parse_name(iname,cname(iname),cform(iname),'uypt',idiag_uypt)
        call parse_name(iname,cname(iname),cform(iname),'uzpt',idiag_uzpt)
        call parse_name(iname,cname(iname),cform(iname),'fintm',idiag_fintm)
        call parse_name(iname,cname(iname),cform(iname),'fextm',idiag_fextm)
        call parse_name(iname,cname(iname),cform(iname),'duxdzma',idiag_duxdzma)
        call parse_name(iname,cname(iname),cform(iname),'duydzma',idiag_duydzma)
      enddo
!
!  check for those quantities for which we want xy-averages
!
      do inamez=1,nnamez
        call parse_name(inamez,cnamez(inamez),cformz(inamez),'uxmz',idiag_uxmz)
        call parse_name(inamez,cnamez(inamez),cformz(inamez),'uymz',idiag_uymz)
        call parse_name(inamez,cnamez(inamez),cformz(inamez),'uzmz',idiag_uzmz)
        call parse_name(inamez,cnamez(inamez),cformz(inamez),'uxuymz',idiag_uxuymz)
        call parse_name(inamez,cnamez(inamez),cformz(inamez),'uxuzmz',idiag_uxuzmz)
        call parse_name(inamez,cnamez(inamez),cformz(inamez),'uyuzmz',idiag_uyuzmz)
        call parse_name(inamez,cnamez(inamez),cformz(inamez),'fmassz',idiag_fmassz)
        call parse_name(inamez,cnamez(inamez),cformz(inamez),'fkinz',idiag_fkinz)
      enddo
!
!  check for those quantities for which we want z-averages
!
      do ixy=1,nnamexy
        call parse_name(ixy,cnamexy(ixy),cformxy(ixy),'uxmxy',idiag_uxmxy)
        call parse_name(ixy,cnamexy(ixy),cformxy(ixy),'uymxy',idiag_uymxy)
        call parse_name(ixy,cnamexy(ixy),cformxy(ixy),'uzmxy',idiag_uzmxy)
      enddo
!
!  check for those quantities for which we want phi-averages
!
      do irz=1,nnamerz
        call parse_name(irz,cnamerz(irz),cformrz(irz),'urmphi',idiag_urmphi)
        call parse_name(irz,cnamerz(irz),cformrz(irz),'upmphi',idiag_upmphi)
        call parse_name(irz,cnamerz(irz),cformrz(irz),'uzmphi',idiag_uzmphi)
        call parse_name(irz,cnamerz(irz),cformrz(irz),'u2mphi',idiag_u2mphi)
        call parse_name(irz,cnamerz(irz),cformrz(irz),'oumphi',idiag_oumphi)
      enddo
!
!  write column where which magnetic variable is stored
!
      if (lwr) then
        write(3,*) 'i_ekin=',idiag_ekin
        write(3,*) 'i_ekintot=',idiag_ekintot
        write(3,*) 'i_u2m=',idiag_u2m
        write(3,*) 'i_um2=',idiag_um2
        write(3,*) 'i_o2m=',idiag_o2m
        write(3,*) 'i_oum=',idiag_oum
        write(3,*) 'i_dtu=',idiag_dtu
        write(3,*) 'i_dtv=',idiag_dtv
        write(3,*) 'i_urms=',idiag_urms
        write(3,*) 'i_umax=',idiag_umax
        write(3,*) 'i_uzrms=',idiag_uzrms
        write(3,*) 'i_uzmax=',idiag_uzmax
        write(3,*) 'i_ux2m=',idiag_ux2m
        write(3,*) 'i_uy2m=',idiag_uy2m
        write(3,*) 'i_uz2m=',idiag_uz2m
        write(3,*) 'i_uxuym=',idiag_uxuym
        write(3,*) 'i_uxuzm=',idiag_uxuzm
        write(3,*) 'i_uyuzm=',idiag_uyuzm
        write(3,*) 'i_ox2m=',idiag_ox2m
        write(3,*) 'i_oy2m=',idiag_oy2m
        write(3,*) 'i_oz2m=',idiag_oz2m
        write(3,*) 'i_oxm=',idiag_oxm
        write(3,*) 'i_oym=',idiag_oym
        write(3,*) 'i_ozm=',idiag_ozm
        write(3,*) 'i_oxoym=',idiag_oxoym
        write(3,*) 'i_oxozm=',idiag_oxozm
        write(3,*) 'i_oyozm=',idiag_oyozm
        write(3,*) 'i_orms=',idiag_orms
        write(3,*) 'i_omax=',idiag_omax
        write(3,*) 'i_ruxm=',idiag_ruxm
        write(3,*) 'i_ruym=',idiag_ruym
        write(3,*) 'i_ruzm=',idiag_ruzm
        write(3,*) 'i_rumax=',idiag_rumax
        write(3,*) 'i_umx=',idiag_umx
        write(3,*) 'i_umy=',idiag_umy
        write(3,*) 'i_umz=',idiag_umz
        write(3,*) 'i_Marms=',idiag_Marms
        write(3,*) 'i_Mamax=',idiag_Mamax
        write(3,*) 'i_divum=',idiag_divum
        write(3,*) 'i_divu2m=',idiag_divu2m
        write(3,*) 'i_u2u13m=',idiag_u2u13m
        write(3,*) 'i_uxpt=',idiag_uxpt
        write(3,*) 'i_uypt=',idiag_uypt
        write(3,*) 'i_uzpt=',idiag_uzpt
        write(3,*) 'i_fmassz=',idiag_fmassz
        write(3,*) 'i_fkinz=',idiag_fkinz
        write(3,*) 'i_uxmz=',idiag_uxmz
        write(3,*) 'i_uymz=',idiag_uymz
        write(3,*) 'i_uzmz=',idiag_uzmz
        write(3,*) 'i_uxmxy=',idiag_uxmxy
        write(3,*) 'i_uymxy=',idiag_uymxy
        write(3,*) 'i_uzmxy=',idiag_uzmxy
        write(3,*) 'i_urmphi=',idiag_urmphi
        write(3,*) 'i_upmphi=',idiag_upmphi
        write(3,*) 'i_uzmphi=',idiag_uzmphi
        write(3,*) 'i_u2mphi=',idiag_u2mphi
        write(3,*) 'i_oumphi=',idiag_oumphi
        write(3,*) 'i_fintm=',idiag_fintm
        write(3,*) 'i_fextm=',idiag_fextm
        write(3,*) 'i_duxdzma=',idiag_duxdzma
        write(3,*) 'i_duydzma=',idiag_duydzma
        write(3,*) 'nname=',nname
        write(3,*) 'iuu=',iuu
        write(3,*) 'iux=',iux
        write(3,*) 'iuy=',iuy
        write(3,*) 'iuz=',iuz
      endif
!
    endsubroutine rprint_hydro
!***********************************************************************
    subroutine calc_mflow
!
!  calculate mean flow field from xy- or z-averages
!
!   8-nov-02/axel: adapted from calc_mfield
!   9-nov-02/axel: allowed mean flow to be compressible
!
      use Cdata
      use Sub
!
      logical,save :: first=.true.
      real, dimension(nx) :: uxmx,uymx,uzmx
      real, dimension(ny,nprocy) :: uxmy,uymy,uzmy
      real :: umx,umy,umz
      integer :: l,j
!
!  Magnetic energy in vertically averaged field
!  The uymxy and uzmxy must have been calculated,
!  so they are present on the root processor.
!
        if (idiag_umx/=0) then
          if(idiag_uymxy==0.or.idiag_uzmxy==0) then
            if(first) print*, 'calc_mflow:                    WARNING'
            if(first) print*, &
                    "calc_mflow: NOTE: to get umx, uymxy and uzmxy must also be set in zaver"
            if(first) print*, &
                    "calc_mflow:      We proceed, but you'll get umx=0"
            umx=0.
          else
            do l=1,nx
              uxmx(l)=sum(fnamexy(l,:,:,idiag_uxmxy))/(ny*nprocy)
              uymx(l)=sum(fnamexy(l,:,:,idiag_uymxy))/(ny*nprocy)
              uzmx(l)=sum(fnamexy(l,:,:,idiag_uzmxy))/(ny*nprocy)
            enddo
            umx=sqrt(sum(uxmx**2+uymx**2+uzmx**2)/nx)
          endif
          call save_name(umx,idiag_umx)
        endif
!
!  similarly for umy
!
        if (idiag_umy/=0) then
          if(idiag_uxmxy==0.or.idiag_uzmxy==0) then
            if(first) print*, 'calc_mflow:                    WARNING'
            if(first) print*, &
                    "calc_mflow: NOTE: to get umy, uxmxy and uzmxy must also be set in zaver"
            if(first) print*, &
                    "calc_mflow:       We proceed, but you'll get umy=0"
            umy=0.
          else
            do j=1,nprocy
            do m=1,ny
              uxmy(m,j)=sum(fnamexy(:,m,j,idiag_uxmxy))/nx
              uymy(m,j)=sum(fnamexy(:,m,j,idiag_uymxy))/nx
              uzmy(m,j)=sum(fnamexy(:,m,j,idiag_uzmxy))/nx
            enddo
            enddo
            umy=sqrt(sum(uxmy**2+uymy**2+uzmy**2)/(ny*nprocy))
          endif
          call save_name(umy,idiag_umy)
        endif
!
!  Kinetic energy in horizontally averaged flow
!  The uxmz and uymz must have been calculated,
!  so they are present on the root processor.
!
        if (idiag_umz/=0) then
          if(idiag_uxmz==0.or.idiag_uymz==0.or.idiag_uzmz==0) then
            if(first) print*,"calc_mflow:                    WARNING"
            if(first) print*, &
                    "calc_mflow: NOTE: to get umz, uxmz, uymz and uzmz must also be set in xyaver"
            if(first) print*, &
                    "calc_mflow:       This may be because we renamed zaver.in into xyaver.in"
            if(first) print*, &
                    "calc_mflow:       We proceed, but you'll get umz=0"
            umz=0.
          else
            umz=sqrt(sum(fnamez(:,:,idiag_uxmz)**2 &
                        +fnamez(:,:,idiag_uymz)**2 &
                        +fnamez(:,:,idiag_uzmz)**2)/(nz*nprocz))
          endif
          call save_name(umz,idiag_umz)
        endif
!
      first = .false.
    endsubroutine calc_mflow
!***********************************************************************
    subroutine calc_turbulence_pars(f)
!
!  Calculate turbulence parameters for a disc. 
!  Currently only works in parallel when nprocy=1
!
!  18-may-04/anders: programmed
!
      use Cdata
      use Cparam
      use Mpicomm
      use EquationOfState, only: pressure_gradient,eoscalc,ilnrho_ss
      use Viscosity, only: nu_mol

      real, dimension(mx,my,mz,mvar+maux) :: f
      real, dimension(nx) ::lnrho,cs2,cp1tilde
      real, dimension(1) :: cs_sum_allprocs_arr,Hp_arr
      real :: cs_sum_thisproc,pp0,pp1,pp2
!
!  Calculate turbulent viscosity
!
      if (tau_nuturb == 0.) then
        nu_turb = nu_turb0
      else
        nu_turb = nu_turb0*exp(-t/tau_nuturb)
        if (nu_turb < nu_turb1) nu_turb = nu_turb1
      endif
!
!  Calculate average sound speed in disc
!
      do m=m1,m2
        do n=n1,n2
          if (ldensity_nolog) then
            lnrho=log(f(l1:l2,m,n,ilnrho))
          else
            lnrho=f(l1:l2,m,n,ilnrho)
          endif
          call pressure_gradient(f,cs2,cp1tilde)
          cs_sum_thisproc = cs_sum_thisproc + sum(sqrt(cs2))
        enddo
      enddo
!
!  Get sum of cs_sum_thisproc_arr on all procs
!
      call mpireduce_sum((/ cs_sum_thisproc /),cs_sum_allprocs_arr,1)
!
!  Calculate average cs
!        
      if (lroot) cs_ave = cs_sum_allprocs_arr(1)/nwgrid
!
!  Send to all procs
!          
      call mpibcast_real(cs_ave,1)
!
!  Need mid-plane pressure for pressure scale height calculation
!
      if (iproc == nprocz/2) then
        if (nprocz == 2*(nprocz/2)) then  ! Even no. of procs in z
          call eoscalc(ilnrho_ss,f(lpoint,mpoint,n1,ilnrho),&
              f(lpoint,mpoint,n1,iss),pp=pp0)
        else                              ! Odd no. of procs in z
          call eoscalc(ilnrho_ss,f(lpoint,mpoint,npoint,ilnrho),&
              f(lpoint,mpoint,npoint,iss),pp=pp0)
        endif
      endif
      call mpibcast_real(pp0,1,nprocz/2)
!
!  Find pressure scale height and calculate turbulence properties
!
      Hp = 0.
      pp2 = 0.
      do n=n1,n2
        pp1 = pp2
        call eoscalc(ilnrho_ss,f(lpoint,mpoint,n,ilnrho), &
            f(lpoint,mpoint,n,iss),pp=pp2)
        if (pp1 > 0.367879*pp0 .and. pp2 <= 0.367879*pp0) then
!
!  Interpolate linearly between z1 and z2 (P_1+(P_2-P_1)/dz*Delta z = 1/e*P_0)
!          
          Hp = z(n-1) + dz/(pp2-pp1)*(0.367879*pp0-pp1)
          exit
        endif
      enddo
!
!  Broadcast scale height to all processors (Hp is 0 except where Hp is found)
!
      call mpireduce_sum((/ Hp /),Hp_arr,1)
      if (lroot) Hp=Hp_arr(1)
      call mpibcast_real(Hp,1)
!  Shakury-Sunyaev alpha      
      alphaSS = nu_turb/(Hp**2*Omega)
!  Speed of largest scale      
      ul0  = alphaSS*cs_ave
!  Eddy turn over time of largest scale      
      tl0  = Hp/ul0
!  Energy dissipation rate for Kolmogorov spectrum      
      eps_diss = nu_turb*(qshear*Omega)**2
!  Speed of smallest (viscous) scale      
      ueta = (nu_mol*eps_diss)**0.25
!  Eddy turn over time of smallest (viscous) scale      
      teta = (nu_mol/eps_diss)**0.5
!  Auxiliary      
      tl01 = 1/tl0
      teta1 = 1/teta

    endsubroutine calc_turbulence_pars
!***********************************************************************

endmodule Hydro
