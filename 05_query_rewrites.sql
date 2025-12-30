-- ============================================================================
-- QUERY REWRITE PATTERNS
-- ============================================================================
-- PURPOSE: Common anti-patterns and their optimized alternatives.
--          Each example shows a slow pattern and a faster rewrite.
--
-- PostgreSQL syntax
-- ============================================================================

-- ============================================================================
-- PATTERN 1: SELECT * vs Specific Columns
-- ============================================================================

-- ❌ ANTI-PATTERN: SELECT * fetches unnecessary data
EXPLAIN ANALYZE
SELECT *
FROM customers
WHERE state = 'CA'
LIMIT 1000;

-- ✅ OPTIMIZED: Select only what you need
EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name, email
FROM customers
WHERE state = 'CA'
LIMIT 1000;

-- WHY IT MATTERS:
--   - Less I/O (fewer bytes read from disk)
--   - Better chance of index-only scan
--   - Reduced network transfer
--   - Won't break if schema changes


-- ============================================================================
-- PATTERN 2: COUNT(*) vs COUNT(column) vs EXISTS
-- ============================================================================

-- Scenario: Check if any orders exist for a customer

-- ❌ SLOW: Counts ALL matching rows
EXPLAIN ANALYZE
SELECT COUNT(*)
FROM orders
WHERE customer_id = 12345;

-- ⚠️ BETTER for existence check: LIMIT 1
EXPLAIN ANALYZE
SELECT 1
FROM orders
WHERE customer_id = 12345
LIMIT 1;

-- ✅ BEST for conditional logic: EXISTS
EXPLAIN ANALYZE
SELECT 
    CASE WHEN EXISTS (
        SELECT 1 FROM orders WHERE customer_id = 12345
    ) THEN 'Has Orders' ELSE 'No Orders' END AS status;

-- WHY EXISTS IS BEST:
--   - Stops at first match (short-circuit evaluation)
--   - COUNT(*) must scan all matching rows


-- ============================================================================
-- PATTERN 3: Correlated Subquery vs JOIN
-- ============================================================================

-- Scenario: Get each customer's latest order date

-- ❌ SLOW: Correlated subquery runs once PER ROW
EXPLAIN ANALYZE
SELECT 
    c.customer_id,
    c.first_name,
    c.last_name,
    (SELECT MAX(o.order_date) 
     FROM orders o 
     WHERE o.customer_id = c.customer_id) AS last_order_date
FROM customers c
WHERE c.state = 'NY'
LIMIT 100;

-- ✅ FASTER: Single aggregation with JOIN
EXPLAIN ANALYZE
SELECT 
    c.customer_id,
    c.first_name,
    c.last_name,
    o.last_order_date
FROM customers c
LEFT JOIN (
    SELECT customer_id, MAX(order_date) AS last_order_date
    FROM orders
    GROUP BY customer_id
) o ON c.customer_id = o.customer_id
WHERE c.state = 'NY'
LIMIT 100;


-- ============================================================================
-- PATTERN 4: Multiple OR vs IN
-- ============================================================================

-- ❌ VERBOSE: Multiple OR conditions
EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name, state
FROM customers
WHERE state = 'CA' 
   OR state = 'NY' 
   OR state = 'TX' 
   OR state = 'FL';

-- ✅ CLEANER: Use IN clause
EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name, state
FROM customers
WHERE state IN ('CA', 'NY', 'TX', 'FL');

-- NOTE: Performance is usually the same, but IN is more readable
-- and easier to maintain (especially with longer lists)


-- ============================================================================
-- PATTERN 5: UNION vs UNION ALL
-- ============================================================================

-- ❌ SLOWER: UNION removes duplicates (requires sort/hash)
EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name, 'CA' AS source
FROM customers WHERE state = 'CA'
UNION
SELECT customer_id, first_name, last_name, 'NY' AS source
FROM customers WHERE state = 'NY';

-- ✅ FASTER: UNION ALL when duplicates are impossible/acceptable
EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name, 'CA' AS source
FROM customers WHERE state = 'CA'
UNION ALL
SELECT customer_id, first_name, last_name, 'NY' AS source
FROM customers WHERE state = 'NY';

-- RULE: Always use UNION ALL unless you specifically need deduplication


-- ============================================================================
-- PATTERN 6: Inefficient Pagination
-- ============================================================================

-- ❌ SLOW for large offsets: OFFSET scans and discards rows
EXPLAIN ANALYZE
SELECT order_id, customer_id, order_date, total_amount
FROM orders
ORDER BY order_date DESC
OFFSET 100000 LIMIT 20;

-- ✅ FASTER: Keyset pagination (seek method)
-- Requires knowing the last value from previous page
EXPLAIN ANALYZE
SELECT order_id, customer_id, order_date, total_amount
FROM orders
WHERE order_date < '2023-06-15'  -- Last date from previous page
ORDER BY order_date DESC
LIMIT 20;

-- WHY KEYSET IS BETTER:
--   - OFFSET 100000 must read and discard 100,000 rows
--   - Keyset seeks directly to the starting point
--   - Performance is consistent regardless of page number


-- ============================================================================
-- PATTERN 7: Calculating Aggregates Multiple Times
-- ============================================================================

-- ❌ INEFFICIENT: Same aggregation computed multiple times
EXPLAIN ANALYZE
SELECT 
    state,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM customers), 2) AS pct_of_total
FROM customers
GROUP BY state
ORDER BY customer_count DESC;

-- ✅ EFFICIENT: Calculate once with window function
EXPLAIN ANALYZE
SELECT 
    state,
    COUNT(*) AS customer_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS pct_of_total
FROM customers
GROUP BY state
ORDER BY customer_count DESC;


-- ============================================================================
-- PATTERN 8: Conditional Aggregation vs Multiple Queries
-- ============================================================================

-- ❌ SLOW: Multiple queries for different conditions
-- Query 1: SELECT COUNT(*) FROM orders WHERE status = 'pending';
-- Query 2: SELECT COUNT(*) FROM orders WHERE status = 'shipped';
-- Query 3: SELECT COUNT(*) FROM orders WHERE status = 'completed';

-- ✅ FAST: Single query with conditional aggregation
EXPLAIN ANALYZE
SELECT 
    COUNT(*) FILTER (WHERE status = 'pending') AS pending_count,
    COUNT(*) FILTER (WHERE status = 'shipped') AS shipped_count,
    COUNT(*) FILTER (WHERE status = 'completed') AS completed_count,
    COUNT(*) AS total_count
FROM orders;

-- PostgreSQL FILTER syntax is cleaner than CASE WHEN:
-- COUNT(*) FILTER (WHERE condition) 
-- vs 
-- SUM(CASE WHEN condition THEN 1 ELSE 0 END)


-- ============================================================================
-- PATTERN 9: Finding Duplicates Efficiently
-- ============================================================================

-- ❌ SLOW: Self-join to find duplicates
EXPLAIN ANALYZE
SELECT DISTINCT a.email
FROM customers a
JOIN customers b ON a.email = b.email AND a.customer_id < b.customer_id
LIMIT 100;

-- ✅ FASTER: GROUP BY with HAVING
EXPLAIN ANALYZE
SELECT email, COUNT(*) AS duplicate_count
FROM customers
GROUP BY email
HAVING COUNT(*) > 1
LIMIT 100;


-- ============================================================================
-- PATTERN 10: UPDATE with Subquery vs FROM Clause
-- ============================================================================

-- ❌ SLOW: Correlated subquery in UPDATE
/*
UPDATE customers c
SET lifetime_value = (
    SELECT COALESCE(SUM(total_amount), 0)
    FROM orders o
    WHERE o.customer_id = c.customer_id
);
*/

-- ✅ FASTER: UPDATE with FROM clause (PostgreSQL)
/*
UPDATE customers c
SET lifetime_value = COALESCE(o.total_spent, 0)
FROM (
    SELECT customer_id, SUM(total_amount) AS total_spent
    FROM orders
    GROUP BY customer_id
) o
WHERE c.customer_id = o.customer_id;
*/

-- NOTE: Commented out to avoid modifying data
-- The FROM clause version is much faster for bulk updates


-- ============================================================================
-- KEY TAKEAWAYS
-- ============================================================================
/*
1. Avoid SELECT * - specify only needed columns
2. Use EXISTS for existence checks, not COUNT(*)
3. Replace correlated subqueries with JOINs when possible
4. Use UNION ALL unless you need deduplication
5. Use keyset pagination for large result sets
6. Window functions avoid repeated scans
7. Conditional aggregation beats multiple queries
8. GROUP BY + HAVING finds duplicates efficiently
9. UPDATE...FROM is faster than correlated UPDATE
*/
