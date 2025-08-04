WITH monthly_revenue AS (
  SELECT 
    FORMAT_DATE('%Y-%m', DATE(oi.created_at)) AS month_year,
    DATE_TRUNC(DATE(oi.created_at), MONTH) AS month_date,
    ROUND(SUM(oi.sale_price), 2) AS total_revenue,
    COUNT(DISTINCT o.order_id) AS total_orders,
    COUNT(oi.id) AS total_items_sold,
    ROUND(AVG(oi.sale_price), 2) AS avg_order_value
  FROM 
    `bigquery-public-data.thelook_ecommerce.order_items` oi
  JOIN 
    `bigquery-public-data.thelook_ecommerce.orders` o
    ON oi.order_id = o.order_id
  WHERE 
    DATE(oi.created_at) >= DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH)
    AND DATE(oi.created_at) < CURRENT_DATE()
    AND o.status NOT IN ('Cancelled', 'Returned')
  GROUP BY 
    1, 2
),

revenue_with_growth AS (
  SELECT 
    month_year,
    month_date,
    total_revenue,
    total_orders,
    total_items_sold,
    avg_order_value,
    
    -- Month-over-Month Growth
    LAG(total_revenue) OVER (ORDER BY month_date) AS prev_month_revenue,
    ROUND(
      SAFE_DIVIDE(
        (total_revenue - LAG(total_revenue) OVER (ORDER BY month_date)),
        LAG(total_revenue) OVER (ORDER BY month_date)
      ) * 100, 2
    ) AS mom_growth_rate,
    
    -- Year-over-Year Growth
    LAG(total_revenue, 12) OVER (ORDER BY month_date) AS prev_year_revenue,
    ROUND(
      SAFE_DIVIDE(
        (total_revenue - LAG(total_revenue, 12) OVER (ORDER BY month_date)),
        LAG(total_revenue, 12) OVER (ORDER BY month_date)
      ) * 100, 2
    ) AS yoy_growth_rate,
    
    -- Running Total
    SUM(total_revenue) OVER (ORDER BY month_date ROWS UNBOUNDED PRECEDING) AS running_total,
    
    -- 3-Month Moving Average
    ROUND(
      AVG(total_revenue) OVER (
        ORDER BY month_date 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
      ), 2
    ) AS three_month_avg
    
  FROM monthly_revenue
)

SELECT 
  month_year,  
  -- Using CONCAT instead of FORMAT for currency
  CONCAT('$', CAST(ROUND(total_revenue, 0) AS STRING)) AS total_revenue,
  total_orders,
  total_items_sold,
  CONCAT('$', CAST(avg_order_value AS STRING)) AS avg_order_value,

  -- Growth Metrics with NULL handling
  CASE 
    WHEN mom_growth_rate IS NULL THEN 'N/A'
    WHEN mom_growth_rate > 0 THEN CONCAT('+', CAST(mom_growth_rate AS STRING), '%')
    ELSE CONCAT(CAST(mom_growth_rate AS STRING), '%')
  END AS mom_growth,
  
  CASE 
    WHEN yoy_growth_rate IS NULL THEN 'N/A'
    WHEN yoy_growth_rate > 0 THEN CONCAT('+', CAST(yoy_growth_rate AS STRING), '%')
    ELSE CONCAT(CAST(yoy_growth_rate AS STRING), '%')
  END AS yoy_growth,
  
  CONCAT('$', CAST(ROUND(running_total, 0) AS STRING)) AS running_total,
  CONCAT('$', CAST(ROUND(three_month_avg, 0) AS STRING)) AS three_month_avg,
  
  -- Trend Indicator
  CASE 
    WHEN mom_growth_rate IS NULL THEN 'First Month'
    WHEN mom_growth_rate > 5 THEN 'Strong Growth'
    WHEN mom_growth_rate > 0 THEN 'Growth'
    WHEN mom_growth_rate > -5 THEN 'Slight Decline'
    ELSE 'Significant Decline'
  END AS trend_indicator

FROM revenue_with_growth
ORDER BY month_date DESC;
