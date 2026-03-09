FUNCTION elap_time() RESULT(t)
!
! Returns elapsed wall-clock time in seconds using system_clock.
! This is a portable replacement for the timing function used in p57.
!
 IMPLICIT NONE
 INTEGER,PARAMETER::iwp=SELECTED_REAL_KIND(15)
 REAL(iwp)::t
 INTEGER::cnt, cnt_rate, cnt_max
 CALL system_clock(cnt, cnt_rate, cnt_max)
 IF (cnt_rate > 0) THEN
   t = REAL(cnt, iwp) / REAL(cnt_rate, iwp)
 ELSE
   t = 0.0_iwp
 END IF
END FUNCTION elap_time
