-- ============================================================================
-- TEST TABLES FOR OPTIMIZATION LAB
-- ============================================================================
-- PURPOSE: Create tables with enough data to demonstrate performance
--          differences between optimized and unoptimized queries.
--
-- NOTE: PostgreSQL syntax. Run this first before other examples.
-- ============================================================================

-- ============================================================================
-- CUSTOMERS TABLE: Main table for query optimization examples
-- ============================================================================

DROP TABLE IF EXISTS order_items CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS customers CASCADE;

CREATE TABLE customers (
    customer_id     SERIAL PRIMARY KEY,
    first_name      VARCHAR(50) NOT NULL,
    last_name       VARCHAR(50) NOT NULL,
    email           VARCHAR(100) NOT NULL,
    phone           VARCHAR(20),
    city            VARCHAR(50),
    state           CHAR(2),
    zip_code        VARCHAR(10),
    created_date    DATE NOT NULL,
    is_active       BOOLEAN DEFAULT true,
    lifetime_value  NUMERIC(12,2) DEFAULT 0
);

-- ============================================================================
-- PRODUCTS TABLE: For join optimization examples
-- ============================================================================

CREATE TABLE products (
    product_id      SERIAL PRIMARY KEY,
    product_name    VARCHAR(100) NOT NULL,
    category        VARCHAR(50),
    unit_price      NUMERIC(10,2) NOT NULL,
    is_active       BOOLEAN DEFAULT true,
    created_date    DATE NOT NULL
);

-- ============================================================================
-- ORDERS TABLE: For join and aggregation examples
-- ============================================================================

CREATE TABLE orders (
    order_id        SERIAL PRIMARY KEY,
    customer_id     INT NOT NULL REFERENCES customers(customer_id),
    order_date      DATE NOT NULL,
    status          VARCHAR(20) DEFAULT 'pending',
    total_amount    NUMERIC(12,2),
    ship_date       DATE,
    ship_city       VARCHAR(50),
    ship_state      CHAR(2)
);

-- ============================================================================
-- ORDER ITEMS TABLE: For multi-table join examples
-- ============================================================================

CREATE TABLE order_items (
    item_id         SERIAL PRIMARY KEY,
    order_id        INT NOT NULL REFERENCES orders(order_id),
    product_id      INT NOT NULL REFERENCES products(product_id),
    quantity        INT NOT NULL,
    unit_price      NUMERIC(10,2) NOT NULL,
    line_total      NUMERIC(12,2) GENERATED ALWAYS AS (quantity * unit_price) STORED
);

-- ============================================================================
-- GENERATE SAMPLE DATA
-- ============================================================================
-- Using generate_series to create realistic volume for testing

-- Insert 100,000 customers
INSERT INTO customers (first_name, last_name, email, phone, city, state, zip_code, created_date, lifetime_value)
SELECT 
    'First' || n AS first_name,
    'Last' || n AS last_name,
    'customer' || n || '@' || 
        CASE (n % 5) 
            WHEN 0 THEN 'gmail.com'
            WHEN 1 THEN 'yahoo.com'
            WHEN 2 THEN 'outlook.com'
            WHEN 3 THEN 'company.com'
            ELSE 'email.com'
        END AS email,
    '555-' || LPAD((n % 10000)::TEXT, 4, '0') AS phone,
    CASE (n % 10)
        WHEN 0 THEN 'New York'
        WHEN 1 THEN 'Los Angeles'
        WHEN 2 THEN 'Chicago'
        WHEN 3 THEN 'Houston'
        WHEN 4 THEN 'Phoenix'
        WHEN 5 THEN 'Philadelphia'
        WHEN 6 THEN 'San Antonio'
        WHEN 7 THEN 'San Diego'
        WHEN 8 THEN 'Dallas'
        ELSE 'Austin'
    END AS city,
    CASE (n % 10)
        WHEN 0 THEN 'NY'
        WHEN 1 THEN 'CA'
        WHEN 2 THEN 'IL'
        WHEN 3 THEN 'TX'
        WHEN 4 THEN 'AZ'
        WHEN 5 THEN 'PA'
        WHEN 6 THEN 'TX'
        WHEN 7 THEN 'CA'
        WHEN 8 THEN 'TX'
        ELSE 'TX'
    END AS state,
    LPAD((10000 + (n % 90000))::TEXT, 5, '0') AS zip_code,
    DATE '2020-01-01' + (n % 1825) AS created_date,  -- ~5 years of dates
    ROUND((RANDOM() * 10000)::NUMERIC, 2) AS lifetime_value
FROM generate_series(1, 100000) AS n;

-- Insert 1,000 products
INSERT INTO products (product_name, category, unit_price, created_date)
SELECT 
    'Product ' || n AS product_name,
    CASE (n % 8)
        WHEN 0 THEN 'Electronics'
        WHEN 1 THEN 'Clothing'
        WHEN 2 THEN 'Home & Garden'
        WHEN 3 THEN 'Sports'
        WHEN 4 THEN 'Books'
        WHEN 5 THEN 'Toys'
        WHEN 6 THEN 'Health'
        ELSE 'Automotive'
    END AS category,
    ROUND((10 + RANDOM() * 490)::NUMERIC, 2) AS unit_price,
    DATE '2020-01-01' + (n % 1825) AS created_date
FROM generate_series(1, 1000) AS n;

-- Insert 500,000 orders
INSERT INTO orders (customer_id, order_date, status, total_amount, ship_date, ship_city, ship_state)
SELECT 
    1 + (n % 100000) AS customer_id,  -- Distribute across customers
    DATE '2022-01-01' + (n % 1095) AS order_date,  -- ~3 years of orders
    CASE (n % 5)
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'processing'
        WHEN 2 THEN 'shipped'
        WHEN 3 THEN 'delivered'
        ELSE 'completed'
    END AS status,
    ROUND((50 + RANDOM() * 950)::NUMERIC, 2) AS total_amount,
    DATE '2022-01-01' + (n % 1095) + 3 AS ship_date,
    CASE (n % 10)
        WHEN 0 THEN 'New York'
        WHEN 1 THEN 'Los Angeles'
        WHEN 2 THEN 'Chicago'
        WHEN 3 THEN 'Houston'
        WHEN 4 THEN 'Phoenix'
        ELSE 'Dallas'
    END AS ship_city,
    CASE (n % 5)
        WHEN 0 THEN 'NY'
        WHEN 1 THEN 'CA'
        WHEN 2 THEN 'IL'
        WHEN 3 THEN 'TX'
        ELSE 'AZ'
    END AS ship_state
FROM generate_series(1, 500000) AS n;

-- Insert 1,500,000 order items (avg 3 items per order)
INSERT INTO order_items (order_id, product_id, quantity, unit_price)
SELECT 
    1 + (n % 500000) AS order_id,
    1 + (n % 1000) AS product_id,
    1 + (n % 5) AS quantity,
    ROUND((10 + RANDOM() * 100)::NUMERIC, 2) AS unit_price
FROM generate_series(1, 1500000) AS n;

-- ============================================================================
-- VERIFY DATA LOAD
-- ============================================================================

SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items;

-- ============================================================================
-- ANALYZE TABLES (update statistics for query planner)
-- ============================================================================

ANALYZE customers;
ANALYZE products;
ANALYZE orders;
ANALYZE order_items;

-- ============================================================================
-- NOTE: At this point, NO indexes exist except primary keys.
-- This allows us to demonstrate before/after performance with indexes.
-- ============================================================================
