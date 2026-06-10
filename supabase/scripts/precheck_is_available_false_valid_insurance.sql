-- 보험 유효 + is_available=false (크론 잔재 vs 의도적 대기 구분 점검)
SELECT
  v.id,
  v.model_name,
  v.car_number,
  v.is_available,
  v.is_under_maintenance,
  v.insurance_expires_at,
  c.name AS complex_name
FROM public.vehicles v
LEFT JOIN public.complexes c ON c.id = v.complex_id
WHERE coalesce(v.is_available, true) = false
  AND coalesce(v.is_under_maintenance, false) = false
  AND (
    v.insurance_expires_at IS NULL
    OR v.insurance_expires_at >= (now() AT TIME ZONE 'Asia/Seoul')::date
  )
ORDER BY c.name, v.model_name;
