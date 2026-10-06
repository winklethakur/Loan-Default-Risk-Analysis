/* =============================================================================
   LOAN DEFAULT RISK DASHBOARD
   MySQL build script
   =============================================================================

   Business question
     Which customer segments have the highest loan default probability, and
     which applications should the credit team manually review?

   Data
     Lending Club accepted loans (Kaggle: wordsforthewise/lending-club).
     Filtered in Python to completed loans only (Fully Paid, Charged Off,
     Default): 1,345,350 rows and 24 columns, saved as loans_filtered.csv.

   How to run
     1. Run the Python filtering step first. It produces loans_filtered.csv.
     2. Edit the file path in the LOAD DATA statement (Section 2).
     3. Run the sections in order. Each section builds on the one before it.

   Table lineage
     stg_loans -> loans_clean -> loans_matured -> loans_binned -> score_points
     -> loans_scored -> loans_tiered -> loans_dashboard and tier_summary

   Power BI reads three tables: loans_dashboard, tier_summary, score_points.

   Contents
     1. Setup
     2. Staging table (raw load)
     3. Clean table
     4. Data quality checks
     5. Matured loans (fair comparison across years)
     6. Segment analysis
     7. Scorecard (buckets, points, scoring, backtest, tiers)
     8. Tables for Power BI
   ============================================================================= */


-- =============================================================================
-- 1. SETUP
-- =============================================================================

CREATE DATABASE loan_risk;
USE loan_risk;

-- LOAD DATA LOCAL needs local_infile to be ON at the server (and the client).
SHOW GLOBAL VARIABLES LIKE 'local_infile';


-- =============================================================================
-- 2. STAGING TABLE (raw data, loaded exactly as it appears in the CSV)
-- =============================================================================

CREATE TABLE stg_loans (
  id VARCHAR(20),
  loan_amnt DECIMAL(10,2),
  term VARCHAR(20),
  emp_length VARCHAR(20),
  home_ownership VARCHAR(20),
  annual_inc DECIMAL(14,2),
  verification_status VARCHAR(30),
  issue_d VARCHAR(10),
  loan_status VARCHAR(30),
  purpose VARCHAR(30),
  addr_state CHAR(2),
  dti DECIMAL(8,2),
  delinq_2yrs DECIMAL(6,1),
  fico_range_low DECIMAL(6,1),
  fico_range_high DECIMAL(6,1),
  inq_last_6mths DECIMAL(6,1),
  open_acc DECIMAL(6,1),
  pub_rec DECIMAL(6,1),
  revol_bal DECIMAL(14,2),
  revol_util DECIMAL(8,2),
  total_acc DECIMAL(6,1),
  earliest_cr_line VARCHAR(10),
  grade CHAR(1),
  int_rate DECIMAL(6,2)
);

-- Allow loading a local file.
SET GLOBAL local_infile = 1;

-- Load the CSV.
--   * EDIT the file path below to match your machine.
--   * The column list follows the order of the CSV header.
--   * NULLIF turns empty strings into NULL, so missing values are not
--     loaded as 0.
LOAD DATA LOCAL INFILE 'C:/Users/winkle/Downloads/loans_filtered.csv'
INTO TABLE stg_loans
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(@id,@loan_amnt,@term,@int_rate,@grade,@emp_length,@home_ownership,
 @annual_inc,@verification_status,@issue_d,@loan_status,@purpose,
 @addr_state,@dti,@delinq_2yrs,@earliest_cr_line,@fico_range_low,
 @fico_range_high,@inq_last_6mths,@open_acc,@pub_rec,@revol_bal,
 @revol_util,@total_acc)
SET
  id = NULLIF(@id,''),
  loan_amnt = NULLIF(@loan_amnt,''),
  term = NULLIF(TRIM(@term),''),
  int_rate = NULLIF(@int_rate,''),
  grade = NULLIF(@grade,''),
  emp_length = NULLIF(@emp_length,''),
  home_ownership = NULLIF(@home_ownership,''),
  annual_inc = NULLIF(@annual_inc,''),
  verification_status = NULLIF(@verification_status,''),
  issue_d = NULLIF(@issue_d,''),
  loan_status = NULLIF(@loan_status,''),
  purpose = NULLIF(@purpose,''),
  addr_state = NULLIF(@addr_state,''),
  dti = NULLIF(@dti,''),
  delinq_2yrs = NULLIF(@delinq_2yrs,''),
  earliest_cr_line = NULLIF(@earliest_cr_line,''),
  fico_range_low = NULLIF(@fico_range_low,''),
  fico_range_high = NULLIF(@fico_range_high,''),
  inq_last_6mths = NULLIF(@inq_last_6mths,''),
  open_acc = NULLIF(@open_acc,''),
  pub_rec = NULLIF(@pub_rec,''),
  revol_bal = NULLIF(@revol_bal,''),
  revol_util = NULLIF(@revol_util,''),
  total_acc = NULLIF(@total_acc,'');

-- Check 1: row count. Expected: 1,345,350
SELECT COUNT(*) FROM stg_loans;

-- Check 2: loan status mix. Expected: mostly Fully Paid, about 20% Charged Off,
-- and only a handful of Default.
SELECT loan_status, COUNT(*) AS loans
FROM stg_loans
GROUP BY loan_status;

-- Check 3: look at the first rows.
SELECT * FROM stg_loans LIMIT 3;

-- Housekeeping.
-- An abandoned Import Wizard attempt left a partial table called loans_filtered
-- (25,819 rows). It does not exist in a fresh build, so the two statements that
-- refer to it are commented out. Un-comment them only if that table exists.
-- SELECT COUNT(*) FROM loans_filtered;
-- DROP TABLE loans_filtered;

SELECT COUNT(*) FROM stg_loans;
SHOW TABLES;


-- =============================================================================
-- 3. CLEAN TABLE (typed columns plus derived fields)
-- =============================================================================
--   term_months          term as a number (36 or 60)
--   emp_years            employment length as a number (NULL = not provided)
--   issue_date / year    parsed from text such as 'Dec-2015'
--   default_flag         1 = Charged Off or Default, 0 = Fully Paid
--   fico_avg             average of the FICO low and high range
--   grade, int_rate      kept for reference only, NOT used in the score
--                        (they are the lender's own risk assessment)

CREATE TABLE loans_clean AS
SELECT
  id,
  loan_amnt,
  CAST(REPLACE(term,' months','') AS UNSIGNED)           AS term_months,
  emp_length,
  CASE
    WHEN emp_length IS NULL        THEN NULL
    WHEN emp_length = '< 1 year'   THEN 0
    WHEN emp_length = '10+ years'  THEN 10
    ELSE CAST(SUBSTRING_INDEX(emp_length,' ',1) AS UNSIGNED)
  END                                                    AS emp_years,
  home_ownership,
  annual_inc,
  verification_status,
  STR_TO_DATE(CONCAT('01-',issue_d),'%d-%b-%Y')          AS issue_date,
  YEAR(STR_TO_DATE(CONCAT('01-',issue_d),'%d-%b-%Y'))    AS issue_year,
  loan_status,
  CASE WHEN loan_status IN ('Charged Off','Default')
       THEN 1 ELSE 0 END                                 AS default_flag,
  purpose,
  addr_state,
  dti,
  delinq_2yrs,
  (fico_range_low + fico_range_high) / 2                 AS fico_avg,
  inq_last_6mths,
  open_acc,
  pub_rec,
  revol_bal,
  revol_util,
  total_acc,
  grade,
  int_rate
FROM stg_loans;

-- Indexes to speed up later queries.
ALTER TABLE loans_clean
  ADD INDEX idx_year (issue_year),
  ADD INDEX idx_state (addr_state),
  ADD INDEX idx_purpose (purpose);

-- The same index statement appeared a second time in the original script.
-- It is commented out because running it twice fails with error 1061
-- (Duplicate key name).
-- ALTER TABLE loans_clean
--   ADD INDEX idx_year (issue_year),
--   ADD INDEX idx_state (addr_state),
--   ADD INDEX idx_purpose (purpose);

-- Check: row count. Expected: 1,345,350
SELECT COUNT(*) FROM loans_clean;

-- Check: overall default rate. Expected: about 20%
SELECT COUNT(*) AS loans, ROUND(AVG(default_flag)*100,2) AS default_pct
FROM loans_clean;


-- =============================================================================
-- 4. DATA QUALITY CHECKS
-- =============================================================================

-- A) Duplicate ids. Expected: 0
SELECT COUNT(*) - COUNT(DISTINCT id) AS dup_ids FROM loans_clean;

-- B) Missing values.
-- Expected: null_income 0, null_emp 78,516, null_dti 374, null_revol 857,
--           null_fico 0, bad_dates 0
SELECT
  SUM(annual_inc IS NULL)  AS null_income,
  SUM(emp_length IS NULL)  AS null_emp,
  SUM(dti IS NULL)         AS null_dti,
  SUM(revol_util IS NULL)  AS null_revol,
  SUM(fico_avg IS NULL)    AS null_fico,
  SUM(issue_date IS NULL)  AS bad_dates
FROM loans_clean;

-- C) Strange values.
-- Expected: income from 0 to 10,999,200 (361 loans with zero income);
--           dti from -1 to 999 (placeholder codes); 535 odd dti values
SELECT MIN(annual_inc), MAX(annual_inc),
       SUM(annual_inc = 0)       AS zero_income,
       MIN(dti), MAX(dti),
       SUM(dti < 0 OR dti > 100) AS odd_dti
FROM loans_clean;

-- D) Default rate by issue year (all completed loans).
-- Note: the 2014 to 2018 rates are distorted, because loans that are still
-- running were removed. Section 5 fixes this.
SELECT issue_year, COUNT(*) AS loans,
       ROUND(AVG(default_flag)*100,2) AS default_pct
FROM loans_clean
GROUP BY issue_year
ORDER BY issue_year;


-- =============================================================================
-- 5. MATURED LOANS (fair comparison across years)
-- =============================================================================
-- Loans that are still running ("Current") were removed in the Python step.
-- That leaves only the early finishers in recent years, which makes their
-- default rates look wrong. To compare years fairly, keep only loans whose full
-- term ended before the data was collected (end of 2018). Every loan in the
-- sample has then had the same time to succeed or fail.

-- The same year-by-year query, matured loans only.
-- Result: 2007 to 2015 remain. From 2009 to 2015 the rates are steady (12.6% to
-- 16.2%). 2007 (17.93%) and 2008 (15.81%) rest on only 251 and 1,562 loans.
SELECT issue_year,
       COUNT(*) AS loans,
       ROUND(AVG(default_flag)*100,2) AS default_pct
FROM loans_clean
WHERE DATE_ADD(issue_date, INTERVAL term_months MONTH) <= '2018-12-01'
GROUP BY issue_year
ORDER BY issue_year;

-- Confirm loans_clean exists.
SHOW TABLES;

CREATE TABLE loans_matured AS
SELECT *
FROM loans_clean
WHERE DATE_ADD(issue_date, INTERVAL term_months MONTH) <= '2018-12-01';

ALTER TABLE loans_matured
  ADD INDEX idx_year (issue_year),
  ADD INDEX idx_purpose (purpose),
  ADD INDEX idx_state (addr_state);

-- Check. Expected: 673,553 loans and a default rate of 14.81% (the baseline).
SELECT COUNT(*) AS loans,
       ROUND(AVG(default_flag)*100,2) AS default_pct
FROM loans_matured;


-- =============================================================================
-- 6. SEGMENT ANALYSIS (default rate by borrower and loan characteristic)
-- =============================================================================
-- Baseline is 14.81%. A segment above it is riskier than average.
-- Always read the loan count next to the rate: small groups are noisy.

-- 6.1 Loan term (36 vs 60 months).
-- Expected: 36 months 13.90%, 60 months 25.16%
SELECT term_months,
       COUNT(*) AS loans,
       ROUND(AVG(default_flag)*100,2) AS default_pct
FROM loans_matured
GROUP BY term_months;

-- 6.2 Loan purpose (loan type).
-- Expected: small_business highest (24.40%), car lowest (11.84%)
SELECT purpose,
       COUNT(*) AS loans,
       ROUND(AVG(default_flag)*100,2) AS default_pct
FROM loans_matured
GROUP BY purpose
HAVING COUNT(*) >= 1000
ORDER BY default_pct DESC;

-- 6.3 Income bracket.
-- Expected: falls at every step, from 20.70% (under 30k) to 10.27% (150k+)
-- The 'Unknown' group has only 2 loans, so the scorecard folds it into Under 30k.
SELECT
  CASE
    WHEN annual_inc IS NULL OR annual_inc = 0 THEN '0 Unknown'
    WHEN annual_inc < 30000   THEN '1 Under 30k'
    WHEN annual_inc < 50000   THEN '2 30k-50k'
    WHEN annual_inc < 75000   THEN '3 50k-75k'
    WHEN annual_inc < 100000  THEN '4 75k-100k'
    WHEN annual_inc < 150000  THEN '5 100k-150k'
    ELSE '6 150k+'
  END AS income_bracket,
  COUNT(*) AS loans,
  ROUND(AVG(default_flag)*100,2) AS default_pct
FROM loans_matured
GROUP BY income_bracket
ORDER BY income_bracket;

-- 6.4 Employment length.
-- Expected: known lengths are flat (13.7% to 15.2%); Unknown stands out (20.84%)
-- The scorecard merges 1-2, 3-5 and 6-9 years into one group because they are flat.
SELECT
  CASE
    WHEN emp_years IS NULL THEN '0 Unknown'
    WHEN emp_years = 0     THEN '1 Under 1 yr'
    WHEN emp_years <= 2    THEN '2 1-2 yrs'
    WHEN emp_years <= 5    THEN '3 3-5 yrs'
    WHEN emp_years <= 9    THEN '4 6-9 yrs'
    ELSE '5 10+ yrs'
  END AS emp_bucket,
  COUNT(*) AS loans,
  ROUND(AVG(default_flag)*100,2) AS default_pct
FROM loans_matured
GROUP BY emp_bucket
ORDER BY emp_bucket;

-- 6.5 State (geography).
-- Expected: MS highest (18.68%), DC lowest (9.95%).
-- Shown for analysis only. State is NOT used in the risk score.
SELECT addr_state,
       COUNT(*) AS loans,
       ROUND(AVG(default_flag)*100,2) AS default_pct
FROM loans_matured
GROUP BY addr_state
HAVING COUNT(*) >= 1000
ORDER BY default_pct DESC;

-- 6.6 Term effect within the same years.
-- Checks that the 60-month result is not just an effect of the years.
-- Expected: 60-month loans fail 11 to 14 points more in every year.
SELECT issue_year, term_months,
       COUNT(*) AS loans,
       ROUND(AVG(default_flag)*100,2) AS default_pct
FROM loans_matured
WHERE issue_year BETWEEN 2010 AND 2013
GROUP BY issue_year, term_months
ORDER BY issue_year, term_months;

-- 6.7 FICO score.
-- Expected: falls from 19.07% (under 680) to 6.05% (750+)
SELECT
  CASE
    WHEN fico_avg IS NULL THEN '0 Unknown'
    WHEN fico_avg < 680   THEN '1 Under 680'
    WHEN fico_avg < 700   THEN '2 680-699'
    WHEN fico_avg < 720   THEN '3 700-719'
    WHEN fico_avg < 750   THEN '4 720-749'
    ELSE '5 750+'
  END AS fico_bucket,
  COUNT(*) AS loans,
  ROUND(AVG(default_flag)*100,2) AS default_pct
FROM loans_matured
GROUP BY fico_bucket
ORDER BY fico_bucket;

-- 6.8 DTI (debt-to-income).
-- Expected: rises from 11.46% (under 10) to about 20.6% (30 and above)
-- The 40+ group has only 29 loans, so the scorecard merges it into 30+.
SELECT
  CASE
    WHEN dti IS NULL OR dti < 0 OR dti > 100 THEN '0 Unknown'
    WHEN dti < 10 THEN '1 Under 10'
    WHEN dti < 20 THEN '2 10-19'
    WHEN dti < 30 THEN '3 20-29'
    WHEN dti < 40 THEN '4 30-39'
    ELSE '5 40+'
  END AS dti_bucket,
  COUNT(*) AS loans,
  ROUND(AVG(default_flag)*100,2) AS default_pct
FROM loans_matured
GROUP BY dti_bucket
ORDER BY dti_bucket;


-- =============================================================================
-- 7. SCORECARD
-- =============================================================================
-- Points for each factor group = how many percentage points its default rate is
-- above or below the training average. A loan's risk score is the sum of six
-- factors: term, purpose, income, employment, FICO and DTI.
-- State is left out of the score on purpose (fair lending concern).
-- grade and int_rate are left out (the lender's own risk assessment).
--
-- The points are calculated on training loans (issued 2007 to 2013) and tested on
-- loans the score has never seen (issued 2014 to 2015).

-- 7.1 Put every loan into its group for each factor.
-- Small groups are merged: employment 1 to 9 years, income Unknown into
-- Under 30k, DTI 30 and above, and rare purposes into 'other'.
CREATE TABLE loans_binned AS
SELECT
  id,
  issue_year,
  CASE WHEN issue_year <= 2013 THEN 'train' ELSE 'test' END AS period,
  default_flag,
  CASE WHEN term_months = 36 THEN '36 months' ELSE '60 months' END AS term_bin,
  CASE WHEN purpose IN ('educational','renewable_energy') THEN 'other'
       ELSE purpose END AS purpose_bin,
  CASE
    WHEN annual_inc IS NULL OR annual_inc < 30000 THEN '1 Under 30k'
    WHEN annual_inc < 50000  THEN '2 30k-50k'
    WHEN annual_inc < 75000  THEN '3 50k-75k'
    WHEN annual_inc < 100000 THEN '4 75k-100k'
    WHEN annual_inc < 150000 THEN '5 100k-150k'
    ELSE '6 150k+'
  END AS income_bin,
  CASE
    WHEN emp_years IS NULL THEN '1 Unknown'
    WHEN emp_years = 0     THEN '2 Under 1 yr'
    WHEN emp_years <= 9    THEN '3 1-9 yrs'
    ELSE '4 10+ yrs'
  END AS emp_bin,
  CASE
    WHEN fico_avg IS NULL OR fico_avg < 680 THEN '1 Under 680'
    WHEN fico_avg < 700 THEN '2 680-699'
    WHEN fico_avg < 720 THEN '3 700-719'
    WHEN fico_avg < 750 THEN '4 720-749'
    ELSE '5 750+'
  END AS fico_bin,
  CASE
    WHEN dti IS NULL OR dti < 0 OR dti > 100 THEN '2 10-19'
    WHEN dti < 10 THEN '1 Under 10'
    WHEN dti < 20 THEN '2 10-19'
    WHEN dti < 30 THEN '3 20-29'
    ELSE '4 30+'
  END AS dti_bin
FROM loans_matured;

-- Check. Expected: train 227,957 loans at 15.50%, test 445,596 loans at 14.46%
SELECT period, COUNT(*) AS loans, ROUND(AVG(default_flag)*100,2) AS default_pct
FROM loans_binned
GROUP BY period;

-- 7.2 Build the points table (the scorecard itself), from training loans only.
CREATE TABLE score_points AS
SELECT factor, bin, loans,
       ROUND(default_pct, 2) AS default_pct,
       CAST(ROUND(default_pct - base_pct) AS SIGNED) AS points
FROM (
  SELECT 'term' AS factor, term_bin AS bin, COUNT(*) AS loans,
         AVG(default_flag)*100 AS default_pct
  FROM loans_binned WHERE period = 'train' GROUP BY term_bin
  UNION ALL
  SELECT 'purpose', purpose_bin, COUNT(*), AVG(default_flag)*100
  FROM loans_binned WHERE period = 'train' GROUP BY purpose_bin
  UNION ALL
  SELECT 'income', income_bin, COUNT(*), AVG(default_flag)*100
  FROM loans_binned WHERE period = 'train' GROUP BY income_bin
  UNION ALL
  SELECT 'employment', emp_bin, COUNT(*), AVG(default_flag)*100
  FROM loans_binned WHERE period = 'train' GROUP BY emp_bin
  UNION ALL
  SELECT 'fico', fico_bin, COUNT(*), AVG(default_flag)*100
  FROM loans_binned WHERE period = 'train' GROUP BY fico_bin
  UNION ALL
  SELECT 'dti', dti_bin, COUNT(*), AVG(default_flag)*100
  FROM loans_binned WHERE period = 'train' GROUP BY dti_bin
) t
CROSS JOIN (
  SELECT AVG(default_flag)*100 AS base_pct
  FROM loans_binned WHERE period = 'train'
) b;

-- The scorecard. Expected: 33 rows, for example 60 months +10, small_business +10,
-- FICO under 680 +5, FICO 750+ -8
SELECT * FROM score_points ORDER BY factor, bin;

-- 7.3 Score every loan by adding the six points.
CREATE TABLE loans_scored AS
SELECT
  b.id, b.issue_year, b.period, b.default_flag,
  b.term_bin, b.purpose_bin, b.income_bin, b.emp_bin, b.fico_bin, b.dti_bin,
  p_term.points + p_purpose.points + p_income.points
    + p_emp.points + p_fico.points + p_dti.points AS risk_score
FROM loans_binned b
JOIN score_points p_term    ON p_term.factor    = 'term'       AND p_term.bin    = b.term_bin
JOIN score_points p_purpose ON p_purpose.factor = 'purpose'    AND p_purpose.bin = b.purpose_bin
JOIN score_points p_income  ON p_income.factor  = 'income'     AND p_income.bin  = b.income_bin
JOIN score_points p_emp     ON p_emp.factor     = 'employment' AND p_emp.bin     = b.emp_bin
JOIN score_points p_fico    ON p_fico.factor    = 'fico'       AND p_fico.bin    = b.fico_bin
JOIN score_points p_dti     ON p_dti.factor     = 'dti'        AND p_dti.bin     = b.dti_bin;

ALTER TABLE loans_scored ADD INDEX idx_score (risk_score);

-- Check. Expected: 673,553 loans, minimum score -24, maximum score 33
SELECT COUNT(*) AS loans, MIN(risk_score) AS min_score, MAX(risk_score) AS max_score
FROM loans_scored;

-- 7.4 Backtest: does a higher score mean a higher default rate?
-- Expected: the rate rises with the score in both train and test.
-- Scores of 20 and above have almost no test loans, because high scores need a
-- 60-month loan and those exist only in the training years.
SELECT FLOOR(risk_score/5)*5 AS score_band,
       SUM(period = 'train') AS train_loans,
       ROUND(100*SUM(CASE WHEN period='train' THEN default_flag END)/SUM(period='train'),2) AS train_default_pct,
       SUM(period = 'test') AS test_loans,
       ROUND(100*SUM(CASE WHEN period='test' THEN default_flag END)/SUM(period='test'),2) AS test_default_pct
FROM loans_scored
GROUP BY score_band
ORDER BY score_band;

-- 7.5 Assign the risk tiers.
-- Tier 1: -11 or lower | Tier 2: -10 to -1 | Tier 3: 0 to 4
-- Tier 4: 5 to 9       | Tier 5: 10 or higher
CREATE TABLE loans_tiered AS
SELECT s.*,
  CASE
    WHEN risk_score <= -11 THEN 'Tier 1 Very Low'
    WHEN risk_score <= -1  THEN 'Tier 2 Low'
    WHEN risk_score <= 4   THEN 'Tier 3 Medium'
    WHEN risk_score <= 9   THEN 'Tier 4 High'
    ELSE 'Tier 5 Very High'
  END AS risk_tier
FROM loans_scored s;

ALTER TABLE loans_tiered ADD INDEX idx_tier (risk_tier);

-- Check the tiers on train, test and all loans.
-- Expected (all loans): 5.30%, 10.86%, 16.16%, 21.17%, 28.63% from Tier 1 to Tier 5
SELECT risk_tier,
       COUNT(*) AS loans,
       ROUND(100*AVG(CASE WHEN period='train' THEN default_flag END),2) AS train_default_pct,
       ROUND(100*AVG(CASE WHEN period='test'  THEN default_flag END),2) AS test_default_pct,
       ROUND(100*AVG(default_flag),2) AS all_default_pct
FROM loans_tiered
GROUP BY risk_tier
ORDER BY risk_tier;


-- =============================================================================
-- 8. TABLES FOR POWER BI
-- =============================================================================

-- 8.1 One row per loan, with the score, tier and readable details.
CREATE TABLE loans_dashboard AS
SELECT
  t.id,
  t.issue_year,
  t.period,
  t.default_flag,
  t.risk_score,
  t.risk_tier,
  CAST(SUBSTRING(t.risk_tier, 6, 1) AS UNSIGNED) AS tier_no,
  m.loan_amnt,
  m.term_months,
  m.purpose,
  m.annual_inc,
  t.income_bin,
  m.emp_length,
  t.emp_bin,
  ROUND(m.fico_avg) AS fico_avg,
  t.fico_bin,
  m.dti,
  t.dti_bin,
  m.addr_state
FROM loans_tiered t
JOIN loans_matured m ON m.id = t.id;

-- Check. Expected: 673,553
SELECT COUNT(*) FROM loans_dashboard;

-- 8.2 Review trade-off by tier.
-- pct_apps_reviewed and pct_defaults_caught are cumulative: each tier includes
-- every riskier tier above it.
CREATE TABLE tier_summary AS
SELECT risk_tier, tier_no, loans, defaults,
       ROUND(100*defaults/loans, 2) AS default_pct,
       ROUND(100*SUM(loans) OVER (ORDER BY tier_no DESC) / SUM(loans) OVER (), 1) AS pct_apps_reviewed,
       ROUND(100*SUM(defaults) OVER (ORDER BY tier_no DESC) / SUM(defaults) OVER (), 1) AS pct_defaults_caught
FROM (
  SELECT risk_tier, tier_no, COUNT(*) AS loans, SUM(default_flag) AS defaults
  FROM loans_dashboard
  GROUP BY risk_tier, tier_no
) t;

-- Expected: Tier 5 = 8.0% of applications and 15.5% of failures;
--           Tiers 4 and 5 = 24.5% and 39.0%
SELECT * FROM tier_summary ORDER BY tier_no;