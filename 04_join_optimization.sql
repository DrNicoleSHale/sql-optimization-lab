-- ============================================================================
-- JOIN OPTIMIZATION
-- ============================================================================
-- PURPOSE: Demonstrate strategies for optimizing multi-table joins.
--
-- PostgreSQL supports three join algorithms:
--   1. Nested Loop - Good for small tables or indexed lookups
--   2. Hash Join - Good for medium tables without indexes
--   3. Merge Join - Good for large, pre-sorted datasets
--
-- PostgreSQL syntax
-- ============================================================================

-- Ensure we have indexes for join columns
CREATE INDEX IF NOT EXISTS ix_orders_customer_id ON orders(customer_id);
CREATE INDEX IF NOT EXISTS ix_order_items_order_id ON order_items(order_id);
CREATE INDEX IF NOT EXISTS ix_order_items_product_id ON order_items(product_id);

ANALYZE customers;
ANALYZE orders;
ANALYZE order_items;
ANALYZE products;

-- ============================================================================
-- EXAMPLE 1: The Importance of Foreign Key Indexes
-- ============================================================================

-- Check if index exists on FK column
SELECT indexname, indexdef 
FROM pg_indexes 
WHERE tablename = 'orders' AND indexdef LIKE '%customer_id%';

-- WITH INDEX: Efficient Nested Loop or Hash Join
EXPLAIN ANALYZE
SELECT c.customer_id, c.first_name, c.last_name, COUNT(o.order_id) AS order_count
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE c.state = 'CA'
GROUP BY c.customer_id, c.first_name, c.last_name;

-- KEY INSIGHT: Without ix_orders_customer_id, this would be MUCH slower
-- PostgreSQL would need to scan the entire orders table for each customer


-- ============================================================================
-- EXAMPLE 2: Join Order Matters (Sometimes)
-- ============================================================================
-- PostgreSQL's optimizer usually picks the best join order,
-- but understanding the concept helps with complex queries.

-- Scenario: Find all order details for Texas customers in 2024

-- Let PostgreSQL choose (usually optimal)
EXPLAIN ANALYZE
SELECT c.first_name, c.last_name, o.order_date, p.product_name, oi.quantity
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
WHERE c.state = 'TX'
  AND o.order_date >= '2024-01-01';

-- The optimizer considers:
--   - Table sizes (customers < orders < order_items)
--   - Selectivity of filters (state = 'TX', date range)
--   - Available indexes
--   - Join column statistics


-- ============================================================================
-- EXAMPLE 3: Reduce Rows BEFORE Joining
-- ============================================================================
-- Filter early to minimize the number of rows in subsequent joins

-- ❌ LESS EFFICIENT: Filter after all joins
EXPLAIN ANALYZE
SELECT c.first_name, c.last_name, o.order_date, o.total_amount
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE c.state = 'NY' 
  AND o.order_date >= '2024-06-01'
  AND o.total_amount > 500;

-- ✅ MORE EFFICIENT: Use CTEs to filter first (if optimizer doesn't)
EXPLAIN ANALYZE
WITH ny_customers AS (
    SELECT customer_id, first_name, last_name
    FROM customers
    WHERE state = 'NY'
),
recent_big_orders AS (
    SELECT order_id, customer_id, order_date, total_amount
    FROM orders
    WHERE order_date >= '2024-06-01'
      AND total_amount > 500
)
SELECT nc.first_name, nc.last_name, rbo.order_date, rbo.total_amount
FROM ny_customers nc
JOIN recent_big_orders rbo ON nc.customer_id = rbo.customer_id;

-- NOTE: Modern PostgreSQL often optimizes both the same way.
-- Check EXPLAIN to see if the CTE approach helps your specific case.


-- ============================================================================
-- EXAMPLE 4: EXISTS vs JOIN for Semi-Joins
-- ============================================================================
-- "Find customers who have placed at least one order"

-- Using JOIN (may produce duplicates, needs DISTINCT)
EXPLAIN ANALYZE
SELECT DISTINCT c.customer_id, c.first_name, c.last_name
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE c.state = 'CA';

-- Using EXISTS (no duplicates, often faster)
EXPLAIN ANALYZE
SELECT c.customer_id, c.first_name, c.last_name
FROM customers c
WHERE c.state = 'CA'
  AND EXISTS (
    SELECT 1 FROM orders o WHERE o.customer_id = c.customer_id
  );

-- WHY EXISTS IS OFTEN BETTER:
--   - Stops scanning after first match (short-circuit)
--   - No need for DISTINCT (saves a sort/hash operation)
--   - Clearer intent: "has at least one"


-- ============================================================================
-- EXAMPLE 5: LEFT JOIN Pitfalls
-- ============================================================================

-- Scenario: All customers with their order count (including zero)

-- ✅ CORRECT: Count handles NULLs properly
EXPLAIN ANALYZE
SELECT c.customer_id, c.first_name, COUNT(o.order_id) AS order_count
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
WHERE c.state = 'AZ'
GROUP BY c.customer_id, c.first_name;

-- ❌ WRONG: WHERE clause on right table converts to INNER JOIN!
EXPLAIN ANALYZE
SELECT c.customer_id, c.first_name, COUNT(o.order_id) AS order_count
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
WHERE c.state = 'AZ'
  AND o.status = 'completed'  -- This REMOVES customers with no orders!
GROUP BY c.customer_id, c.first_name;

-- ✅ CORRECT: Filter in the JOIN condition instead
EXPLAIN ANALYZE
SELECT c.customer_id, c.first_name, COUNT(o.order_id) AS completed_orders
FROM customers c
LEFT JOIN orders o ON c.customer_id = o.customer_id
                   AND o.status = 'completed'
WHERE c.state = 'AZ'
GROUP BY c.customer_id, c.first_name;


-- ============================================================================
-- EXAMPLE 6: Aggregating Before Joining
-- ============================================================================
-- When joining to get aggregates, aggregate FIRST then join

-- ❌ SLOWER: Join all rows, then aggregate
EXPLAIN ANALYZE
SELECT c.customer_id, c.first_name, c.last_name,
       SUM(o.total_amount) AS total_spent,
       COUNT(o.order_id) AS order_count
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE c.state = 'TX'
GROUP BY c.customer_id, c.first_name, c.last_name;

-- ✅ FASTER: Aggregate first, then join for details
EXPLAIN ANALYZE
WITH customer_totals AS (
    SELECT customer_id,
           SUM(total_amount) AS total_spent,
           COUNT(order_id) AS order_count
    FROM orders
    GROUP BY customer_id
)
SELECT c.customer_id, c.first_name, c.last_name,
       ct.total_spent, ct.order_count
FROM customers c
JOIN customer_totals ct ON c.customer_id = ct.customer_id
WHERE c.state = 'TX';

-- WHY FASTER:
--   - Aggregation happens on smaller intermediate result
--   - Join processes fewer rows


-- ============================================================================
-- EXAMPLE 7: Avoiding Cartesian Products
-- ============================================================================

-- ❌ ACCIDENTAL CARTESIAN: Missing or wrong join condition
-- This query would return customers × products rows!
-- DON'T RUN THIS - it's just to illustrate the danger

/*
SELECT c.first_name, p.product_name
FROM customers c, products p
WHERE c.state = 'CA';
-- Missing: AND c.??? = p.???
*/

-- ✅ ALWAYS explicitly specify join conditions
SELECT c.first_name, p.product_name, oi.quantity
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
JOIN order_items oi ON o.order_id = oi.order_id
JOIN products p ON oi.product_id = p.product_id
WHERE c.state = 'CA'
LIMIT 100;


-- ============================================================================
-- EXAMPLE 8: Choosing the Right Join Type
-- ============================================================================
/*
| Need                                    | Use This Join    |
|-----------------------------------------|------------------|
| Only matching rows from both tables     | INNER JOIN       |
| All from left, matching from right      | LEFT JOIN        |
| All from right, matching from left      | RIGHT JOIN       |
| All from both, match where possible     | FULL OUTER JOIN  |
| Check if match exists (no duplicates)   | EXISTS/NOT EXISTS|
| Cross-reference all combinations        | CROSS JOIN       |
*/


-- ============================================================================
-- KEY TAKEAWAYS
-- ============================================================================
/*
1. Always index foreign key columns
2. Use EXISTS for "has any" checks instead of JOIN + DISTINCT
3. Filter as early as possible to reduce join sizes
4. Put filters on LEFT JOIN's right table in the ON clause, not WHERE
5. Aggregate before joining when possible
6. Check EXPLAIN ANALYZE - the optimizer is usually smart!
7. Watch for accidental Cartesian products (missing join conditions)
*/
