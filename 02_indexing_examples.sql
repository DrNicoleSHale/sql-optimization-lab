-- ============================================================================
-- INDEXING STRATEGIES
-- ============================================================================
-- PURPOSE: Demonstrate the impact of proper index design on query performance.
--
-- HOW TO USE:
--   1. Run each "BEFORE" query with EXPLAIN ANALYZE
--   2. Create the suggested index
--   3. Run the "AFTER" query and compare
--
-- PostgreSQL syntax
-- ============================================================================

-- ============================================================================
-- EXAMPLE 1: Basic B-Tree Index
-- ============================================================================
-- Scenario: Find customers created in a specific date range

-- BEFORE: No index on created_date
-- Expected: Sequential Scan (slow on large tables)

EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name, email, created_date
FROM customers
WHERE created_date >= '2024-01-01' 
  AND created_date < '2024-04-01';

-- CREATE THE INDEX
CREATE INDEX ix_customers_created_date ON customers(created_date);

-- AFTER: Index Scan (much faster)
-- Run the same query again and compare execution time

EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name, email, created_date
FROM customers
WHERE created_date >= '2024-01-01' 
  AND created_date < '2024-04-01';

-- WHAT CHANGED:
--   - "Seq Scan" becomes "Index Scan" or "Bitmap Index Scan"
--   - Execution time drops dramatically (often 10-100x)


-- ============================================================================
-- EXAMPLE 2: Composite Index (Multi-Column)
-- ============================================================================
-- Scenario: Find orders by status within a date range
-- Key insight: Column ORDER matters in composite indexes!

-- BEFORE: No index
EXPLAIN ANALYZE
SELECT order_id, customer_id, order_date, status, total_amount
FROM orders
WHERE order_date >= '2024-01-01'
  AND status = 'shipped';

-- CREATE COMPOSITE INDEX
-- Put the equality column (status) FIRST, range column (order_date) SECOND
-- This is the "equality before range" rule

CREATE INDEX ix_orders_status_date ON orders(status, order_date);

-- AFTER: Uses composite index efficiently
EXPLAIN ANALYZE
SELECT order_id, customer_id, order_date, status, total_amount
FROM orders
WHERE order_date >= '2024-01-01'
  AND status = 'shipped';

-- WHY STATUS FIRST?
--   - Equality (=) narrows to exact values immediately
--   - Range (>=, <=) then scans within that subset
--   - Reverse order would scan ALL dates, then filter by status


-- ============================================================================
-- EXAMPLE 3: Covering Index (Index-Only Scan)
-- ============================================================================
-- Scenario: Dashboard query that only needs specific columns
-- Goal: Avoid touching the table entirely

-- Query we want to optimize
EXPLAIN ANALYZE
SELECT customer_id, email, created_date
FROM customers
WHERE created_date >= '2024-01-01'
ORDER BY created_date;

-- CREATE COVERING INDEX using INCLUDE
-- The INCLUDE columns are stored in the index but not part of the search key

CREATE INDEX ix_customers_created_covering 
ON customers(created_date) 
INCLUDE (customer_id, email);

-- AFTER: Index-Only Scan (fastest possible)
EXPLAIN ANALYZE
SELECT customer_id, email, created_date
FROM customers
WHERE created_date >= '2024-01-01'
ORDER BY created_date;

-- LOOK FOR: "Index Only Scan" in the explain output
-- This means PostgreSQL never touched the table heap!


-- ============================================================================
-- EXAMPLE 4: Partial Index (Filtered Index)
-- ============================================================================
-- Scenario: Most queries only care about active customers
-- Insight: Why index rows you'll never query?

-- Query pattern: Always filtering for active customers
EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name, email
FROM customers
WHERE is_active = true
  AND state = 'CA';

-- CREATE PARTIAL INDEX (only indexes active customers)
CREATE INDEX ix_customers_active_state 
ON customers(state) 
WHERE is_active = true;

-- AFTER: Smaller index, faster queries
EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name, email
FROM customers
WHERE is_active = true
  AND state = 'CA';

-- BENEFITS:
--   - Index is much smaller (only active rows)
--   - Faster to scan and maintain
--   - Perfect for "soft delete" patterns


-- ============================================================================
-- EXAMPLE 5: Index for Foreign Key Joins
-- ============================================================================
-- Scenario: Joining orders to customers
-- Common mistake: Forgetting to index foreign keys

-- BEFORE: No index on orders.customer_id
EXPLAIN ANALYZE
SELECT c.first_name, c.last_name, o.order_date, o.total_amount
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE c.state = 'TX';

-- CREATE INDEX on foreign key
CREATE INDEX ix_orders_customer_id ON orders(customer_id);

-- AFTER: Much faster joins
EXPLAIN ANALYZE
SELECT c.first_name, c.last_name, o.order_date, o.total_amount
FROM customers c
JOIN orders o ON c.customer_id = o.customer_id
WHERE c.state = 'TX';

-- NOTE: PostgreSQL does NOT auto-create indexes on foreign keys!
-- Always check your FK columns have indexes.


-- ============================================================================
-- EXAMPLE 6: Index for ORDER BY (Avoiding Sorts)
-- ============================================================================
-- Scenario: Paginated results need consistent ordering

-- BEFORE: Requires a sort operation
EXPLAIN ANALYZE
SELECT order_id, customer_id, order_date, total_amount
FROM orders
WHERE status = 'completed'
ORDER BY order_date DESC
LIMIT 100;

-- CREATE INDEX that matches the ORDER BY
CREATE INDEX ix_orders_status_date_desc ON orders(status, order_date DESC);

-- AFTER: No sort needed - index provides order
EXPLAIN ANALYZE
SELECT order_id, customer_id, order_date, total_amount
FROM orders
WHERE status = 'completed'
ORDER BY order_date DESC
LIMIT 100;

-- LOOK FOR: "Sort" disappears from the plan
-- The index delivers rows in the correct order


-- ============================================================================
-- CLEANUP: View all indexes we created
-- ============================================================================

SELECT 
    indexname,
    indexdef
FROM pg_indexes
WHERE tablename IN ('customers', 'orders', 'products', 'order_items')
  AND indexname NOT LIKE '%pkey'
ORDER BY tablename, indexname;


-- ============================================================================
-- KEY TAKEAWAYS
-- ============================================================================
/*
1. ALWAYS check execution plans before and after adding indexes
2. Composite indexes: equality columns first, range columns second
3. Covering indexes eliminate table access entirely
4. Partial indexes are perfect for filtered queries
5. Foreign keys need explicit indexes in PostgreSQL
6. Index order can eliminate expensive sort operations
7. More indexes = slower writes, so be strategic
*/
