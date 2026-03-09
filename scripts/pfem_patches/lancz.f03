SUBROUTINE lancz1(neq,el,er,acc,leig,lx,lalfa,lp,iflag,ua,va,eig,jeig,   &
  neig,x,del,nu,alfa,beta,v_store)
!-------------------------------------------------------------------------
! Reverse-communication block Lanczos eigenvalue routine.
! Finds eigenvalues of a symmetric matrix C in the range [el,er].
! Uses the tridiagonal Lanczos recurrence; convergence checked via
! Sturm sequence on the accumulated tridiagonal T_j.
!
! Protocol (reverse communication):
!   iflag=-1  : first call; initialises and outputs va=v_1, iflag=1
!   iflag= 1  : caller provides ua += C*va; lancz1 advances one step
!               and either outputs new va (iflag=1) or signals done (iflag=0)
!   iflag= 0  : converged; eig(1:neig) contains eigenvalues
!   iflag= 2  : failure (max iterations reached without convergence)
!-------------------------------------------------------------------------
 IMPLICIT NONE
 INTEGER,PARAMETER::iwp=SELECTED_REAL_KIND(15)
 INTEGER,INTENT(IN)::neq,leig,lx,lalfa,lp
 INTEGER,INTENT(IN OUT)::iflag,neig
 REAL(iwp),INTENT(IN)::el,er,acc
 REAL(iwp),INTENT(IN OUT)::ua(0:neq),va(0:neq)
 REAL(iwp),INTENT(IN OUT)::eig(leig),alfa(lalfa),beta(lalfa)
 REAL(iwp),INTENT(IN OUT)::x(lx),del(lx)
 REAL(iwp),INTENT(IN OUT)::v_store(0:neq,lalfa)
 INTEGER,INTENT(IN OUT)::jeig(2,leig),nu(lx)
!
 REAL(iwp)::zero=0.0_iwp,one=1.0_iwp,alph,bet,rnorm,tmp
 INTEGER::i,j,k,nstrum_lo,nstrum_hi,p
!
! ── Saved state across calls ─────────────────────────────────────────────
 INTEGER,SAVE::jstep=0          ! current Lanczos step
 REAL(iwp),SAVE::beta_prev=0.0_iwp
 INTEGER,SAVE::neig_old=0       ! eigenvalue count at previous check
!
! ── First call: initialise ───────────────────────────────────────────────
 IF(iflag==-1)THEN
   jstep=0; beta_prev=zero; neig_old=0
   alfa=zero; beta=zero
   ! Starting vector: uniform, then orthonormalized
   rnorm=zero
   DO i=1,neq
     va(i)=one/SQRT(REAL(neq,iwp))
   END DO
   va(0)=zero
   v_store(:,1)=va
   ua=zero
   iflag=1
   RETURN
 END IF
!
! ── Continuation call: advance Lanczos step ──────────────────────────────
 jstep=jstep+1
!
! alpha_j = < v_j , C*v_j >
 alph=DOT_PRODUCT(v_store(1:neq,jstep), ua(1:neq))
 alfa(jstep)=alph
!
! w = C*v_j - alpha_j*v_j - beta_{j-1}*v_{j-1}
 DO i=1,neq
   ua(i)=ua(i)-alph*v_store(i,jstep)
 END DO
 IF(jstep>1)THEN
   DO i=1,neq
     ua(i)=ua(i)-beta_prev*v_store(i,jstep-1)
   END DO
 END IF
!
! beta_j = ||w||
 bet=SQRT(DOT_PRODUCT(ua(1:neq),ua(1:neq)))
 beta(jstep)=bet
!
! ── Convergence check via Sturm sequence ─────────────────────────────────
! Count eigenvalues of tridiagonal T_j in [el,er] using Sturm sequences.
 IF(jstep>=2)THEN
   CALL sturm_count(jstep,alfa,beta,el,nstrum_lo)
   CALL sturm_count(jstep,alfa,beta,er,nstrum_hi)
   neig=nstrum_hi-nstrum_lo
   IF(neig>leig)neig=leig
!
!  Extract Ritz values (eigenvalues of T_j) in [el,er]
   CALL trid_eig(jstep,alfa,beta,el,er,neig,eig,jeig,acc)
!
!  Check if converged: small beta or count stable and beta < acc
   IF(bet<=acc .OR. (neig==neig_old .AND. neig>0 .AND. bet<=SQRT(acc)))THEN
     iflag=0
     RETURN
   END IF
   neig_old=neig
 END IF
!
! ── Not converged: compute next Lanczos vector ───────────────────────────
 IF(jstep>=lalfa)THEN
   iflag=2  ! max iterations, could not converge
   RETURN
 END IF
!
 IF(bet>acc)THEN
   DO i=1,neq
     v_store(i,jstep+1)=ua(i)/bet
   END DO
 ELSE
   ! beta≈0: restart with a new random-ish vector (simple restart)
   DO i=1,neq
     v_store(i,jstep+1)=zero
   END DO
   IF(jstep+1<=neq)v_store(jstep+1,jstep+1)=one
 END IF
 v_store(0,jstep+1)=zero
!
 beta_prev=bet
 va=v_store(:,jstep+1)
 ua=zero   ! caller must accumulate C*va fresh
 iflag=1
END SUBROUTINE lancz1

!=========================================================================

SUBROUTINE lancz2(neq,lalfa,lp,eig,jeig,neig,alfa,beta,lz,jflag,y,w1,z, &
  v_store)
!-------------------------------------------------------------------------
! Reconstruct Ritz eigenvectors from Lanczos basis.
! y(:,i) = V_lalfa * z_i  where z_i = eigenvector of tridiagonal T.
!-------------------------------------------------------------------------
 IMPLICIT NONE
 INTEGER,PARAMETER::iwp=SELECTED_REAL_KIND(15)
 INTEGER,INTENT(IN)::neq,lalfa,lp,neig,lz
 INTEGER,INTENT(OUT)::jflag
 REAL(iwp),INTENT(IN)::eig(neig),alfa(lalfa),beta(lalfa)
 INTEGER,INTENT(IN)::jeig(2,neig)
 REAL(iwp),INTENT(OUT)::y(0:neq,neig)
 REAL(iwp),INTENT(IN OUT)::w1(0:neq)
 REAL(iwp),INTENT(IN OUT)::z(lz,neig)
 REAL(iwp),INTENT(IN)::v_store(0:neq,lalfa)
 REAL(iwp)::zero=0.0_iwp,one=1.0_iwp,tmp,rnorm
 INTEGER::i,j,k,nj
!
 jflag=0
 nj=MIN(lalfa,lz)   ! number of Lanczos steps actually taken
!
! For each eigenvalue, compute the corresponding eigenvector of T
 DO k=1,neig
   CALL trid_evec(nj,alfa,beta,eig(k),z(1:nj,k))
 END DO
!
! Ritz vectors: y_k = V * z_k
 y=zero
 DO k=1,neig
   DO j=1,nj
     DO i=1,neq
       y(i,k)=y(i,k)+v_store(i,j)*z(j,k)
     END DO
   END DO
   ! Normalise
   rnorm=SQRT(DOT_PRODUCT(y(1:neq,k),y(1:neq,k)))
   IF(rnorm>zero)y(1:neq,k)=y(1:neq,k)/rnorm
 END DO
END SUBROUTINE lancz2

!=========================================================================

SUBROUTINE sturm_count(n,alfa,beta,shift,count)
!
! Count eigenvalues of symmetric tridiagonal T less than shift
! using the Sturm sequence.
!
 IMPLICIT NONE
 INTEGER,PARAMETER::iwp=SELECTED_REAL_KIND(15)
 INTEGER,INTENT(IN)::n
 REAL(iwp),INTENT(IN)::alfa(n),beta(n),shift
 INTEGER,INTENT(OUT)::count
 REAL(iwp)::q,tiny=1.0E-30_iwp
 INTEGER::i
!
 count=0
 q=alfa(1)-shift
 IF(q<0.0_iwp)count=count+1
 DO i=2,n
   IF(ABS(q)<tiny)q=tiny
   q=(alfa(i)-shift)-beta(i-1)**2/q
   IF(q<0.0_iwp)count=count+1
 END DO
END SUBROUTINE sturm_count

!=========================================================================

SUBROUTINE trid_eig(n,alfa,beta,el,er,neig,eig,jeig,acc)
!
! Find eigenvalues of symmetric tridiagonal T in [el,er] by bisection.
! Uses Sturm sequences to bracket each eigenvalue.
!
 IMPLICIT NONE
 INTEGER,PARAMETER::iwp=SELECTED_REAL_KIND(15)
 INTEGER,INTENT(IN)::n,neig
 REAL(iwp),INTENT(IN)::alfa(n),beta(n),el,er,acc
 REAL(iwp),INTENT(OUT)::eig(neig)
 INTEGER,INTENT(OUT)::jeig(2,neig)
 INTEGER::cnt_lo,cnt_hi,cnt_mid,k,iter
 REAL(iwp)::lo,hi,mid
!
 CALL sturm_count(n,alfa,beta,el,cnt_lo)
 CALL sturm_count(n,alfa,beta,er,cnt_hi)
!
 DO k=1,neig
   ! k-th eigenvalue is between indices cnt_lo+k-1 and cnt_lo+k
   ! Find by bisection
   lo=el; hi=er
   DO iter=1,200
     mid=(lo+hi)*0.5_iwp
     CALL sturm_count(n,alfa,beta,mid,cnt_mid)
     IF(cnt_mid<cnt_lo+k)THEN
       lo=mid
     ELSE
       hi=mid
     END IF
     IF(hi-lo<acc*(1.0_iwp+ABS(mid)))EXIT
   END DO
   eig(k)=(lo+hi)*0.5_iwp
   jeig(1,k)=cnt_lo+k-1
   jeig(2,k)=cnt_lo+k
 END DO
END SUBROUTINE trid_eig

!=========================================================================

SUBROUTINE trid_evec(n,alfa,beta,eval,evec)
!
! Compute eigenvector of symmetric tridiagonal T for eigenvalue eval
! using inverse iteration.
!
 IMPLICIT NONE
 INTEGER,PARAMETER::iwp=SELECTED_REAL_KIND(15)
 INTEGER,INTENT(IN)::n
 REAL(iwp),INTENT(IN)::alfa(n),beta(n),eval
 REAL(iwp),INTENT(OUT)::evec(n)
 REAL(iwp)::d(n),e(n-1),shift,rnorm,tiny=1.0E-10_iwp
 INTEGER::i,iter
!
 ! Use power iteration / QR to get evec: simpler approach —
 ! solve (T - eval*I)*x = b using LU with small shift to avoid singularity
 shift=eval+tiny
 d=alfa-shift
 ! Forward substitution (Thomas algorithm for tridiagonal)
 evec=1.0_iwp/SQRT(REAL(n,iwp))  ! start with uniform vector
!
 DO iter=1,50
   ! Solve (T - shift*I) * evec_new = evec using Thomas algorithm
   CALL trid_solve(n,alfa-shift,beta,evec,evec)
   rnorm=SQRT(DOT_PRODUCT(evec,evec))
   IF(rnorm>0.0_iwp)evec=evec/rnorm
 END DO
!
END SUBROUTINE trid_evec

!=========================================================================

SUBROUTINE trid_solve(n,d,e,rhs,x)
!
! Solve symmetric tridiagonal system (diag=d, off-diag=e(1..n-1)) * x = rhs
! using Thomas algorithm (Gaussian elimination for tridiagonal).
!
 IMPLICIT NONE
 INTEGER,PARAMETER::iwp=SELECTED_REAL_KIND(15)
 INTEGER,INTENT(IN)::n
 REAL(iwp),INTENT(IN)::d(n),e(n-1),rhs(n)
 REAL(iwp),INTENT(OUT)::x(n)
 REAL(iwp)::c(n),w,tiny=1.0E-30_iwp
 INTEGER::i
!
 c=d
 x=rhs
 DO i=2,n
   IF(ABS(c(i-1))<tiny)c(i-1)=tiny
   w=e(i-1)/c(i-1)
   c(i)=c(i)-w*e(i-1)
   x(i)=x(i)-w*x(i-1)
 END DO
 IF(ABS(c(n))<tiny)c(n)=tiny
 x(n)=x(n)/c(n)
 DO i=n-1,1,-1
   x(i)=(x(i)-e(i)*x(i+1))/c(i)
 END DO
END SUBROUTINE trid_solve
