-- ============================================================================
-- SARGABLE QUERIES
-- ============================================================================
-- PURPOSE: Demonstrate the critical difference between SARGable and
--          non-SARGable predicates in WHERE clauses.
--
-- SARGable = Search ARGument ABLE
-- A predicate is SARGable if the database can use an index seek.
-- Functions on columns typically BREAK SARGability.
--
-- PostgreSQL syntax
-- ============================================================================

-- First, ensure we have an index to work with
CREATE INDEX IF NOT EXISTS ix_customers_created_date ON customers(created_date);
CREATE INDEX IF NOT EXISTS ix_orders_order_date ON orders(order_date);
CREATE INDEX IF NOT EXISTS ix_customers_email ON customers(email);

ANALYZE customers;
ANALYZE orders;

-- ============================================================================
-- EXAMPLE 1: Date Functions (Most Common Mistake!)
-- ============================================================================

-- ❌ NON-SARGABLE: Function on the column
-- PostgreSQL CANNOT use the index - must scan every row

EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name, created_date
FROM customers
WHERE EXTRACT(YEAR FROM created_date) = 2024;

-- ✅ SARGABLE: Range comparison on the column itself
-- PostgreSQL CAN use the index - seeks directly to matching rows

EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name, created_date
FROM customers
WHERE created_date >= '2024-01-01' 
  AND created_date < '2025-01-01';

-- PERFORMANCE DIFFERENCE: Often 10-100x faster!


-- ============================================================================
-- EXAMPLE 2: String Functions
-- ============================================================================

-- ❌ NON-SARGABLE: UPPER() on column
EXPLAIN ANALYZE
SELECT customer_id, email
FROM customers
WHERE UPPER(email) = 'CUSTOMER100@GMAIL.COM';

-- ✅ SARGABLE: Use ILIKE for case-insensitive (PostgreSQL)
EXPLAIN ANALYZE
SELECT customer_id, email
FROM customers
WHERE email ILIKE 'customer100@gmail.com';

-- ✅ ALTERNATIVE: Create an expression index (if this query runs often)
CREATE INDEX ix_customers_email_upper ON customers(UPPER(email));

-- Now this becomes SARGable!
EXPLAIN ANALYZE
SELECT customer_id, email
FROM customers
WHERE UPPER(email) = 'CUSTOMER100@GMAIL.COM';


-- ============================================================================
-- EXAMPLE 3: Math Operations on Columns
-- ============================================================================

-- ❌ NON-SARGABLE: Arithmetic on column
EXPLAIN ANALYZE
SELECT order_id, total_amount
FROM orders
WHERE total_amount * 1.1 > 500;

-- ✅ SARGABLE: Move math to the constant side
EXPLAIN ANALYZE
SELECT order_id, total_amount
FROM orders
WHERE total_amount > 500 / 1.1;

-- ❌ NON-SARGABLE: Addition on column
EXPLAIN ANALYZE
SELECT order_id, total_amount
FROM orders
WHERE total_amount + 50 > 500;

-- ✅ SARGABLE: Subtract from constant instead
EXPLAIN ANALYZE
SELECT order_id, total_amount
FROM orders
WHERE total_amount > 450;


-- ============================================================================
-- EXAMPLE 4: COALESCE and NULL Handling
-- ============================================================================

-- ❌ NON-SARGABLE: COALESCE on column
EXPLAIN ANALYZE
SELECT customer_id, phone
FROM customers
WHERE COALESCE(phone, 'NONE') = '555-0001';

-- ✅ SARGABLE: Direct comparison (handle NULL separately if needed)
EXPLAIN ANALYZE
SELECT customer_id, phone
FROM customers
WHERE phone = '555-0001';


-- ============================================================================
-- EXAMPLE 5: LIKE Patterns
-- ============================================================================

-- Create index for this example
CREATE INDEX IF NOT EXISTS ix_customers_last_name ON customers(last_name);

-- ✅ SARGABLE: Prefix pattern (starts with)
-- Index CAN be used - PostgreSQL knows where to start looking
EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name
FROM customers
WHERE last_name LIKE 'Smith%';

-- ❌ NON-SARGABLE: Suffix pattern (ends with)
-- Index CANNOT be used - could be anywhere in the index
EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name
FROM customers
WHERE last_name LIKE '%son';

-- ❌ NON-SARGABLE: Contains pattern
-- Index CANNOT be used
EXPLAIN ANALYZE
SELECT customer_id, first_name, last_name
FROM customers
WHERE last_name LIKE '%mit%';

-- TIP: For suffix/contains searches, consider:
--   - Full-text search (tsvector/tsquery)
--   - pg_trgm extension with GIN index
--   - Reverse index for suffix searches


-- ============================================================================
-- EXAMPLE 6: OR Conditions
-- ============================================================================

-- Create indexes for this example
CREATE INDEX IF NOT EXISTS ix_customers_state ON customers(state);
CREATE INDEX IF NOT EXISTS ix_customers_city ON customers(city);

-- ⚠️ OR can prevent index use (depends on optimizer)
EXPLAIN ANALYZE
SELECT customer_id, first_name, city, state
FROM customers
WHERE state = 'CA' OR city = 'Houston';

-- ✅ BETTER: UNION ALL (guarantees index use on each part)
EXPLAIN ANALYZE
SELECT customer_id, first_name, city, state
FROM customers
WHERE state = 'CA'
UNION ALL
SELECT customer_id, first_name, city, state
FROM customers
WHERE city = 'Houston'
  AND state != 'CA';  -- Avoid duplicates


-- ============================================================================
-- EXAMPLE 7: NOT IN vs NOT EXISTS
-- ============================================================================

-- ⚠️ NOT IN can be slow and has NULL issues
EXPLAIN ANALYZE
SELECT c.customer_id, c.first_name, c.last_name
FROM customers c
WHERE c.customer_id NOT IN (
    SELECT DISTINCT customer_id FROM orders WHERE order_date >= '2024-01-01'
);

-- ✅ NOT EXISTS is usually faster and NULL-safe
EXPLAIN ANALYZE
SELECT c.customer_id, c.first_name, c.last_name
FROM customers c
WHERE NOT EXISTS (
    SELECT 1 FROM orders o 
    WHERE o.customer_id = c.customer_id 
      AND o.order_date >= '2024-01-01'
);


-- ============================================================================
-- EXAMPLE 8: Implicit Type Conversion
-- ============================================================================

-- ❌ NON-SARGABLE: Comparing different types forces conversion
-- If zip_code is VARCHAR but you compare to an integer:

EXPLAIN ANALYZE
SELECT customer_id, zip_code
FROM customers
WHERE zip_code = 10001;  -- Integer compared to VARCHAR

-- ✅ SARGABLE: Use matching types
EXPLAIN ANALYZE
SELECT customer_id, zip_code
FROM customers
WHERE zip_code = '10001';  -- String compared to VARCHAR


-- ============================================================================
-- QUICK REFERENCE: SARGABLE TRANSFORMATIONS
-- ============================================================================
/*
| Non-SARGable                    | SARGable Equivalent                    |
|---------------------------------|----------------------------------------|
| YEAR(date_col) = 2024           | date_col >= '2024-01-01' AND           |
|                                 | date_col < '2025-01-01'                |
| MONTH(date_col) = 6             | date_col >= '2024-06-01' AND           |
|                                 | date_col < '2024-07-01'                |
| UPPER(col) = 'X'                | col ILIKE 'x' (PostgreSQL)             |
| col + 1 = 5                     | col = 4                                |
| col * 2 > 100                   | col > 50                               |
| COALESCE(col, 'x') = 'x'        | col = 'x' OR col IS NULL               |
| col LIKE '%abc'                 | Use full-text search or pg_trgm        |
| col NOT IN (subquery)           | NOT EXISTS (correlated subquery)       |
*/


-- ============================================================================
-- KEY TAKEAWAYS
-- ============================================================================
/*
1. Never apply functions to columns in WHERE clauses
2. Move arithmetic to the constant side of comparisons
3. Prefix LIKE patterns are SARGable; suffix/contains are not
4. Use explicit type matching to avoid implicit conversions
5. NOT EXISTS usually outperforms NOT IN
6. When in doubt, check EXPLAIN ANALYZE!
*/
