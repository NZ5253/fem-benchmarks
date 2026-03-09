SUBROUTINE umat(stress,statev,ddsdde,sse,spd,scd,rpl,ddsddt,drplde,       &
  drpldt,stran,dstran,time,dtime,temp,dtemp,predef,dpred,cmname,ndi,nshr, &
  ntens,nstatv,props,nprops,coords,drot,pnewdt,celent,dfgrd0,dfgrd1,      &
  noel,npt,layer,kspt,kstep,kinc)
!-------------------------------------------------------------------------
! Simple isotropic linear-elastic UMAT for PFEM program p57.
! props(1) = E (Young's modulus)
! props(2) = nu (Poisson's ratio)
!-------------------------------------------------------------------------
 IMPLICIT NONE
 INTEGER,PARAMETER::iwp=SELECTED_REAL_KIND(15)
 INTEGER,INTENT(IN)::ndi,nshr,ntens,nstatv,nprops,noel,npt,layer,kspt,    &
   kstep,kinc
 REAL(iwp),INTENT(IN)::stran(ntens),dstran(ntens),time(2),dtime,temp,     &
   dtemp,predef(*),dpred(*),props(nprops),coords(*),drot(3,3),pnewdt,      &
   celent,dfgrd0(3,3),dfgrd1(3,3)
 REAL(iwp),INTENT(IN OUT)::stress(ntens),statev(nstatv)
 REAL(iwp),INTENT(OUT)::ddsdde(ntens,ntens),sse,spd,scd,rpl,              &
   ddsddt(ntens),drplde(ntens),drpldt
 CHARACTER(LEN=80),INTENT(IN)::cmname
 REAL(iwp)::e,nu,lam,mu,zero=0.0_iwp
 INTEGER::i,j
!
 e   = props(1)
 nu  = props(2)
 lam = e * nu / ((1.0_iwp + nu) * (1.0_iwp - 2.0_iwp * nu))
 mu  = e / (2.0_iwp * (1.0_iwp + nu))
!
! Build elastic stiffness DDSDDE
 ddsdde = zero
! Direct (diagonal) terms: lambda + 2*mu for normals, lambda for cross terms
 DO i = 1, ndi
   DO j = 1, ndi
     ddsdde(i,j) = lam
   END DO
   ddsdde(i,i) = lam + 2.0_iwp * mu
 END DO
! Shear terms (Voigt notation: component ndi+1 .. ntens)
 DO i = ndi+1, ntens
   ddsdde(i,i) = mu
 END DO
!
! Update stress: sigma_new = sigma_old + DDSDDE * dstran
 DO i = 1, ntens
   DO j = 1, ntens
     stress(i) = stress(i) + ddsdde(i,j) * dstran(j)
   END DO
 END DO
!
 sse = 0.0_iwp; spd = 0.0_iwp; scd = 0.0_iwp; rpl = 0.0_iwp
 ddsddt = zero; drplde = zero; drpldt = 0.0_iwp
!
END SUBROUTINE umat
