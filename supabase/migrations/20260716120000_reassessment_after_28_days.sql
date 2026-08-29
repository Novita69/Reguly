-- =====================================================================
-- AI Learning Tracker — T2 opens after four complete observation weeks
-- =====================================================================
-- This migration changes ONLY the T2/TAM opening gate from 7 to 28 days.
-- Weekly aggregation remains seven days per week, so weeks 1–4 are kept.

CREATE OR REPLACE FUNCTION public.validate_reassessment_timing()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_baseline_at TIMESTAMPTZ;
  v_existing_count INT;
BEGIN
  IF NEW.assessment_type = 'reassessment' THEN
    SELECT completed_at INTO v_baseline_at
    FROM public.assessment_results
    WHERE user_id = NEW.user_id
      AND assessment_type = 'baseline'
    ORDER BY completed_at ASC
    LIMIT 1;

    IF v_baseline_at IS NULL THEN
      RAISE EXCEPTION 'BASELINE_NOT_COMPLETED: Baseline Assessment (T1) belum diselesaikan.';
    END IF;

    IF NOW() < v_baseline_at + INTERVAL '28 days' THEN
      RAISE EXCEPTION 'REASSESSMENT_LOCKED: SRL Reassessment (T2) baru dapat diisi setelah 28 hari sejak Baseline Assessment selesai.';
    END IF;

    SELECT COUNT(*) INTO v_existing_count
    FROM public.assessment_results
    WHERE user_id = NEW.user_id
      AND assessment_type = 'reassessment';

    IF v_existing_count > 0 THEN
      RAISE EXCEPTION 'REASSESSMENT_ALREADY_DONE: SRL Reassessment (T2) bersifat satu kali (single-cycle) dan sudah pernah diisi.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS before_insert_validate_reassessment
  ON public.assessment_results;
CREATE TRIGGER before_insert_validate_reassessment
  BEFORE INSERT ON public.assessment_results
  FOR EACH ROW
  EXECUTE FUNCTION public.validate_reassessment_timing();

DROP VIEW IF EXISTS public.v_reassessment_gate;

CREATE VIEW public.v_reassessment_gate AS
SELECT
  p.id AS user_id,
  b.baseline_at,
  CASE
    WHEN b.baseline_at IS NOT NULL
      THEN b.baseline_at + INTERVAL '28 days'
  END AS unlock_at,
  COALESCE(
    b.baseline_at IS NOT NULL
    AND NOW() >= b.baseline_at + INTERVAL '28 days',
    FALSE
  ) AS can_reassess,
  (r.reassessment_at IS NOT NULL) AS has_reassessed,
  r.reassessment_at,
  CASE
    WHEN b.baseline_at IS NULL THEN NULL
    ELSE GREATEST(
      0,
      CEIL(
        EXTRACT(EPOCH FROM (
          (b.baseline_at + INTERVAL '28 days') - NOW()
        )) / 86400.0
      )
    )::INT
  END AS days_remaining
FROM public.profiles p
LEFT JOIN (
  SELECT user_id, MIN(completed_at) AS baseline_at
  FROM public.assessment_results
  WHERE assessment_type = 'baseline'
  GROUP BY user_id
) b ON b.user_id = p.id
LEFT JOIN (
  SELECT user_id, MIN(completed_at) AS reassessment_at
  FROM public.assessment_results
  WHERE assessment_type = 'reassessment'
  GROUP BY user_id
) r ON r.user_id = p.id;

GRANT SELECT ON public.v_reassessment_gate TO authenticated;
