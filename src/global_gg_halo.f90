 ! $Id: global_gg_halo.f90,v 1.3 2003-08-13 15:30:07 mee Exp $

module Global

!
!  A module container and access functions (`methods') for additional
!  variables which are globally needed --- here this is the gravity field
!  gg, and the halo profile for identifying a spherical halo region
!  outside a star.
!
!  Tests on Linux boxes show the following performance results when
!  comparing set/get_global access to the global field gg with
!  recomputing gg all the time (ratonal approximation based on cpot):
!
!      size     recomputing    get/set_global  difference
!    ------------------------------------------------------
!      64^3       4.34            3.94           0.40
!     128^3       4.06            3.74           0.32
!     170^3       4.04            3.72           0.32
!
!  Listed are musec/pt/step on Kabul (1.9 GHz Athlon, serial execution).
!

!
  use Cparam
  use Mpicomm

  implicit none

  interface set_global
    module procedure set_global_vect
    module procedure set_global_scal
  endinterface

  interface get_global
    module procedure get_global_vect
    module procedure get_global_scal
  endinterface

!
!  we could (and should in some sense) initialize gg and halo; however,
!  with the Intel compiler this produces significantly larger
!  executables, compiles far longer, and (for 256^3) results in the
!  compiler message `Size of initialised array entity exceeds
!  implementation limit'
!
  real, dimension (mx,my,mz,3) :: gg
  real, dimension (mx,my,mz)   :: halo

  contains

!***********************************************************************
    subroutine set_global_vect(var,m,n,label)
!
!  set (m,n)-pencil of the global vector variable identified by LABEL
!
!  18-jul-02/wolf coded
!
!      use Cparam
!
      real, dimension(nx,3) :: var
      integer :: m,n
      character (len=*) ::label
!
      select case(label)

      case ('gg')
        gg(l1:l2,m,n,1:3) = var

      case default
        if (lroot) print*, 'set_global_vect: No such value for label', trim(label)
        call stop_it('set_global_vect')

      endselect
!
    endsubroutine set_global_vect
!***********************************************************************
    subroutine set_global_scal(var,m,n,label)
!
!  set (m,n)-pencil of the global scalar variable identified by LABEL
!
!  18-jul-02/wolf coded
!
      real, dimension(nx) :: var
      integer :: m,n
      character (len=*) ::label
!
      select case(label)

      case ('halo')
        halo(l1:l2,m,n) = var

      case default
        if (lroot) print*, 'set_global_scal: No such value for label', trim(label)
        call stop_it('set_global_scal')

      endselect
!
    endsubroutine set_global_scal
!***********************************************************************
    subroutine get_global_vect(var,m,n,label)
!
!  set (m,n)-pencil of the global vector variable identified by LABEL
!
!  18-jul-02/wolf coded
!
!      use Cparam
!
      real, dimension(nx,3) :: var
      integer :: m,n
      character (len=*) ::label
!
      select case(label)

      case ('gg')
        var = gg(l1:l2,m,n,1:3)

      case default
        if (lroot) print*, 'get_global_vect: No such value for label', trim(label)
        call stop_it('get_global_vect')

      endselect
!
    endsubroutine get_global_vect
!***********************************************************************
    subroutine get_global_scal(var,m,n,label)
!
!  set (m,n)-pencil of the global scalar variable identified by LABEL
!
!  18-jul-02/wolf coded
!
      real, dimension(nx) :: var
      integer :: m,n
      character (len=*) ::label
!
      select case(label)

      case ('halo')
        var = halo(l1:l2,m,n)

      case default
        if (lroot) print*, 'get_global_scal: No such value for label', trim(label)
        call stop_it('get_global_scal')

      endselect
!
    endsubroutine get_global_scal
!***********************************************************************
    subroutine wglobal()
!
!  write global variables
!
!  10-jan-02/wolf: coded
!
      use Cdata
      use IO
!
      call output(trim(directory)//'/halo.dat',halo,1)
      call output(trim(directory)//'/gg.dat'  ,gg  ,3)
!
    endsubroutine wglobal
!***********************************************************************
    subroutine rglobal()
!
!  read global variables
!
!  10-jan-02/wolf: coded
!
      use Cdata
      use IO
!
      call input(trim(directory)//'/halo.dat',halo,1,0)
      call input(trim(directory)//'/gg.dat'  ,gg  ,3,0)
!
    endsubroutine rglobal
!***********************************************************************

endmodule Global
