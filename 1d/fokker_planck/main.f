c--------------------------------------------------------------------
c Solve linear convection equation with periodic bc
c Author: Praveen. C, http://praveen.tifrbng.res.in
c
c Test case from
c Annunziato & Borzi: Euro. Jnl. of Applied Mathematics (2014)
c vol. 25, pp. 1-15
c
c     f1_t + (a1(x) f1)_x = -mu*f1 + mu*f2
c     f2_t + (a2(x) f2)_x =  mu*f1 - mu*f2
c
c  mu is set in common.inc
c  a1(x) and a2(x) can be set in the functions below
c  For initial condition, edit subroutine set_initial_condition
c  Solution is saved into file sol.dat; plot in gnuplot using
c     bash$ gnuplot plot.gnu
c     bash$ gv sol.eps
c  or with python
c     bash$ python plot.py
c     bash$ xpdf sol.pdf
c--------------------------------------------------------------------
      program main
      implicit none
      include 'common.inc'
      integer nc
      parameter(nc=500)
      real    f1(nc), f1old(nc), res1(nc)
      real    f2(nc), f2old(nc), res2(nc)
      real    xmin, xmax, dx, x(nc), tf, cfl, dt
      integer i, nrk, irk, iter
      real    a1, a2, maxspeed, t
      real    f1min, f1max, f1tot
      real    f2min, f2max, f2tot

      xmin =-2.0  ! Left end of domain
      xmax = 2.0  ! Right end of domain
      tf   = 10.0 ! Final time

c     Set to itvd or iweno
      recon_scheme = iweno

      dx   = (xmax - xmin)/nc

c     Find maximum wave speed
      maxspeed = 0.0
      do i=1,nc
         x(i) = xmin + 0.5*dx + (i-1)*dx
         maxspeed = max(maxspeed, abs(a1(x(i)-0.5*dx)))
         maxspeed = max(maxspeed, abs(a2(x(i)-0.5*dx)))
      enddo
      maxspeed = max(maxspeed, abs(a1(x(nc)+0.5*dx)))
      maxspeed = max(maxspeed, abs(a2(x(nc)+0.5*dx)))

c     Compute time step
      if(recon_scheme.eq.ifirst)then
         cfl = 0.90
         dt = min(1.0/mu, cfl * dx / maxspeed)
         nrk    = 1
         ark(1) = 0.0
      else if(recon_scheme.eq.itvd)then
         cfl = 0.45
         dt = min(1.0/mu, cfl * dx / maxspeed)
         nrk    = 2
         ark(1) = 0.0
         ark(2) = 0.5
      else if(recon_scheme.eq.iweno)then
         cfl = 1.0/12.0
         dt = min(1.0/mu, cfl * dx / (maxspeed + cfl*mu*dx))
         nrk    = 3
         ark(1) = 0.0
         ark(2) = 3.0/4.0
         ark(3) = 1.0/3.0
      endif
      brk(1:nrk) = 1.0 - ark(1:nrk)

      print*,"Maximum speed =", maxspeed
      print*,"Time Step     =", dt

c     set initial condition
      call set_initial_condition(nc, x, f1, f2)
      call compute_range(nc, f1, dx, f1min, f1max, f1tot)
      call compute_range(nc, f2, dx, f2min, f2max, f2tot)
      print*,"Initial range f1 =", f1min, f1max
      print*,"Initial range f2 =", f2min, f2max
      print*,"Total            =", f1tot + f2tot
      call output(nc, x, f1, f2)
      call system("cp sol.dat init.dat")

      t = 0.0
      iter = 0
      do while(t.lt.tf)
         if(t+dt.gt.tf) dt = tf - t
         f1old = f1
         f2old = f2
         do irk=1,nrk
            call compute_residual (1, nc, dx, x, f1, res1, f2)
            call compute_residual (2, nc, dx, x, f2, res2, f1)
            call update_solution (nc, f1, f1old, res1, irk, dt)
            call update_solution (nc, f2, f2old, res2, irk, dt)
         enddo
         call compute_range(nc, f1, dx, f1min, f1max, f1tot)
         call compute_range(nc, f2, dx, f2min, f2max, f2tot)
         t = t + dt
         iter = iter + 1
         if(mod(iter,10).eq.0) call output(nc, x, f1, f2)
         write(*,'(i8,6e14.6)') iter,t,f1min,f1max,f2min,f2max,
     1                          f1tot+f2tot
      enddo
      call output(nc, x, f1, f2)

      stop
      end
c---------------------------------------------------------------------
c     TODO: We have to average initial condition
c---------------------------------------------------------------------
      subroutine set_initial_condition(nc, x, f1, f2)
      implicit none
      integer nc
      real    x(nc), f1(nc), f2(nc)

      integer i
      real    pi
      parameter(pi=4.0*atan(1.0))
      real    c, m, sigma2

      m = 0.0
      sigma2 = 1.0e-2
      c = 1.0/(2.0*sqrt(2.0*pi*sigma2))

      do i=1,nc
         f1(i) = c * exp(-(x(i)-m)**2/(2.0*sigma2))
         f2(i) = c * exp(-(x(i)-m)**2/(2.0*sigma2))
      enddo

      return
      end
c---------------------------------------------------------------------
c Compute residual in the equation
c TODO: Remove periodic bc
c---------------------------------------------------------------------
      subroutine compute_residual (ieqn, nc, dx, x, f1, res1, f0)
      implicit none
      include 'common.inc'
      integer ieqn, nc
      real    dx, x(nc), f1(nc), res1(nc), f0(nc)

      integer i
      real    f1l(nc+1), f1r(nc+1), flux1
      real    pstar, mini, maxi, minf, maxf, theta1, theta2, theta, w1
      parameter(minf=0.0, maxf=1.0e20, w1=1.0/12.0)

      res1(:) = 0.0

c     Compute interface values

c     First face
      f1l(1) = 0.0
      call reconstruct(f1(3),  f1(2),  f1(1), 0.0, 0.0, f1r(1))

c     Second face
      call reconstruct(0.0, 0.0, f1(1), f1(2), f1(3), f1l(2))
      call reconstruct(f1(4),  f1(3),  f1(2),  f1(1), 0.0, f1r(2))

c     Third face
      call reconstruct(0.0, f1(1), f1(2), f1(3), f1(4), f1l(3))
      call reconstruct(f1(5), f1(4), f1(3), f1(2), f1(1), f1r(3))

      do i=3,nc-3
         call reconstruct(f1(i-2), f1(i-1), f1(i), f1(i+1),
     1                    f1(i+2),f1l(i+1))
         call reconstruct(f1(i+3), f1(i+2), f1(i+1), f1(i),
     1                    f1(i-1),f1r(i+1))
      enddo

c     Third face from end
      call reconstruct(f1(nc-4),f1(nc-3),f1(nc-2),f1(nc-1),f1(nc),
     1                 f1l(nc-1))
      call reconstruct(f1(1), f1(nc), f1(nc-1), f1(nc-2),
     1                 f1(nc-3),f1r(nc-1))

c     penultimate face
      call reconstruct(f1(nc-3), f1(nc-2), f1(nc-1), f1(nc),
     1                 f1(1),f1l(nc))
      call reconstruct(f1(2), f1(1), f1(nc), f1(nc-1), f1(nc-2),f1r(nc))

c     Last face
      call reconstruct(f1(nc-2), f1(nc-1), f1(nc), 0.0,
     1                 0.0, f1l(nc+1))
      f1r(nc+1) = 0.0

c     Apply positivity limiter
      if(recon_scheme.eq.iweno)then
         do i=1,nc
            pstar = (f1(i) - w1*f1r(i) - w1*f1l(i+1))/(1.0 - 2*w1)
            mini = min(pstar, min(f1r(i), f1l(i+1)))
            maxi = max(pstar, max(f1r(i), f1l(i+1)))
            theta1 = abs(maxf-f1(i))/(abs(maxi-f1(i))+1.0e-14)
            theta2 = abs(minf-f1(i))/(abs(mini-f1(i))+1.0e-14)
            theta  = min(1.0, min(theta1, theta2))
            f1r(i) = theta*(f1r(i) - f1(i)) + f1(i)
            f1l(i+1) = theta*(f1l(i+1) - f1(i)) + f1(i)
         enddo
      endif

c     Compute fluxes

c     First face
      call num_flux(ieqn, x(1)-0.5*dx, f1l(1), f1r(1), flux1)
      res1(1)  = res1(1)  - flux1

      do i=1,nc-1
         call num_flux(ieqn, x(i+1)-0.5*dx, f1l(i+1), f1r(i+1), flux1)
         res1(i)   = res1(i)   + flux1
         res1(i+1) = res1(i+1) - flux1
      enddo

c     Last face
      call num_flux(ieqn, x(nc)+0.5*dx, f1l(nc+1), f1r(nc+1), flux1)
      res1(nc)  = res1(nc) + flux1

      if(ieqn.eq.1)then
         res1 = res1 - (-mu*f1 + mu*f0)*dx
      else if(ieqn.eq.2)then
         res1 = res1 - ( mu*f0 - mu*f1)*dx
      endif

      res1 = res1/dx

      return
      end
c---------------------------------------------------------------------
c Weno reconstruction
c---------------------------------------------------------------------
      subroutine weno5(um2,um1,u0,up1,up2,u)
      implicit none
      real um2, um1, u0, up1, up2, u
      real eps, gamma1, gamma2, gamma3
      parameter(eps = 1.0e-6, gamma1=1.0/10.0, gamma2=3.0/5.0,
     1          gamma3=3.0/10.0)
      real beta1, beta2, beta3
      real u1, u2, u3;
      real w1, w2, w3;

      beta1 = (13.0/12.0)*(um2 - 2.0*um1 + u0)**2 +
     1  (1.0/4.0)*(um2 - 4.0*um1 + 3.0*u0)**2
      beta2 = (13.0/12.0)*(um1 - 2.0*u0 + up1)**2 +
     1  (1.0/4.0)*(um1 - up1)**2
      beta3 = (13.0/12.0)*(u0 - 2.0*up1 + up2)**2 +
     1  (1.0/4.0)*(3.0*u0 - 4.0*up1 + up2)**2

      w1 = gamma1 / (eps+beta1)**2
      w2 = gamma2 / (eps+beta2)**2
      w3 = gamma3 / (eps+beta3)**2

      u1 = (1.0/3.0)*um2 - (7.0/6.0)*um1 + (11.0/6.0)*u0
      u2 = -(1.0/6.0)*um1 + (5.0/6.0)*u0 + (1.0/3.0)*up1
      u3 = (1.0/3.0)*u0 + (5.0/6.0)*up1 - (1.0/6.0)*up2

      u = (w1 * u1 + w2 * u2 + w3 * u3)/(w1 + w2 + w3)

      return
      end
c---------------------------------------------------------------------
      real function minmod(a, b, c)
      implicit none
      real a, b, c

      if(a*b.lt.0.0.or.b*c.lt.0.0)then
         minmod = 0.0
      else
         minmod = sign(1.0, a) * min(min(abs(a), abs(b)), abs(c))
      endif

      return
      end
c---------------------------------------------------------------------
      subroutine tvd(um2,um1,u0,up1,up2,u)
      implicit none
      real um2, um1, u0, up1, up2, u

      real dul, dur, duc, beta, minmod
      parameter(beta=2.0)

      dul = u0  - um1
      dur = up1 - u0
      duc = up1 - um1

      u = u0 + 0.5 * minmod(0.5*duc, beta*dul, beta*dur)

      return
      end
c---------------------------------------------------------------------
      subroutine reconstruct(um2,um1,u0,up1,up2,u)
      implicit none
      include 'common.inc'
      real um2, um1, u0, up1, up2, u

      if(recon_scheme.eq.ifirst)then
         u = u0
      else if(recon_scheme.eq.itvd)then
         call tvd(um2,um1,u0,up1,up2,u)
      else if(recon_scheme.eq.iweno)then
         call weno5(um2,um1,u0,up1,up2,u)
      else
         print*,"Unknown reconstruction scheme"
         stop
      endif

      return
      end
c---------------------------------------------------------------------
c Wave speed function
c---------------------------------------------------------------------
      real function a1 (x)
      implicit none
      real x

      a1 = 1.0 - x

      return
      end
c---------------------------------------------------------------------
c Wave speed function
c---------------------------------------------------------------------
      real function a2 (x)
      implicit none
      real x

      a2 = -(1.0 + x)

      return
      end
c---------------------------------------------------------------------
c Upwind Numerical flux
c---------------------------------------------------------------------
      subroutine num_flux(ieqn, x, ul, ur, flux)
      implicit none
      integer ieqn
      real    x, ul, ur, flux
      real    a1, a2, a, ep
      parameter(ep=0.1)

      if(ieqn.eq.1)then
         a = a1(x)
      else
         a = a2(x)
      endif

      if(a.gt.0.0)then
         flux = a * ul
      else
         flux = a * ur
      endif

      return
      end
c---------------------------------------------------------------------
c 3-stage 3-order SSP-RK scheme
c---------------------------------------------------------------------
      subroutine update_solution (nc, f1, f1old, res1, irk, dt)
      implicit none
      include 'common.inc'
      integer nc, irk
      real    f1(nc), f1old(nc), res1(nc), dt

      f1 = ark(irk)*f1old + brk(irk)*(f1 - dt * res1)

      return
      end
c---------------------------------------------------------------------
      subroutine compute_range(nc, f1, dx, f1min, f1max, f1tot)
      implicit none
      integer nc
      real    f1(nc), dx, f1min, f1max, f1tot

      integer i

      f1min = 1.0e20
      f1max =-1.0e20
      f1tot = 0.0

      do i=1,nc
         f1min = min(f1min, f1(i))
         f1max = max(f1max, f1(i))
         f1tot = f1tot + f1(i) * dx
      enddo

      return
      end
c---------------------------------------------------------------------
      subroutine output(nc, x, f1, f2)
      implicit none
      integer nc
      real    x(nc), f1(nc), f2(nc)
      integer fid, i

      fid = 10
      open(fid,file="sol.dat")
      write(fid,'(3es24.12e3)')(x(i),f1(i),f2(i),i=1,nc)
      close(fid)

      return
      end
