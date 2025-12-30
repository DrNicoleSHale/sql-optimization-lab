# How to Read PostgreSQL Execution Plans

## Overview

Understanding execution plans is the most important skill for SQL optimization. This guide explains how to read `EXPLAIN` output and identify performance problems.

---

## Basic Commands
```sql
-- Show the plan (estimated costs)
EXPLAIN SELECT * FROM customers WHERE state = 'CA';

-- Show the plan AND run the query (actual times)
EXPLAIN ANALYZE SELECT * FROM customers WHERE state = 'CA';

-- More details (buffers, timing)
EXPLAIN (ANALYZE, BUFFERS, TIMING) SELECT * FROM customers WHERE state = 'CA';

-- Output as JSON (for tools)
EXPLAIN (FORMAT JSON) SELECT * FROM customers WHERE state = 'CA';
```

**Always use EXPLAIN ANALYZE** for real optimization work - estimated costs can be misleading.

---

## Reading the Output
```
Seq Scan on customers  (cost=0.00..2135.00 rows=5000 width=85) (actual time=0.015..18.542 rows=4853 loops=1)
  Filter: (state = 'CA'::bpchar)
  Rows Removed by Filter: 95147
Planning Time: 0.095 ms
Execution Time: 19.125 ms
```

### Breaking It Down

| Part | Meaning |
|------|---------|
| `Seq Scan` | Scan type (see below) |
| `on customers` | Table being accessed |
| `cost=0.00..2135.00` | Estimated startup..total cost (arbitrary units) |
| `rows=5000` | Estimated rows returned |
| `width=85` | Estimated bytes per row |
| `actual time=0.015..18.542` | Real time in milliseconds (first row..last row) |
| `rows=4853` | Actual rows returned |
| `loops=1` | How many times this node executed |
| `Rows Removed by Filter` | Rows examined but not returned |

---

## Scan Types (What to Look For)

### Sequential Scan (Seq Scan) ⚠️
```
Seq Scan on customers
```
- Reads **entire table** from disk
- Fine for small tables
- **Problem** on large tables with selective filters
- **Fix**: Add an index on the filter column

### Index Scan ✅
```
Index Scan using ix_customers_state on customers
```
- Uses index to find rows, then fetches from table
- **Good** for selective queries (few rows returned)
- Watch for high `loops` count

### Index Only Scan ✅✅
```
Index Only Scan using ix_customers_covering on customers
```
- **Best case**: All data comes from index
- Table heap is never touched
- Requires a covering index with INCLUDE columns

### Bitmap Index Scan ✅
```
Bitmap Heap Scan on customers
  -> Bitmap Index Scan on ix_customers_state
```
- Two-phase: Build bitmap from index, then fetch rows
- **Good** for medium selectivity
- Efficient for OR conditions and multiple indexes

---

## Join Types

### Nested Loop
```
Nested Loop
  -> Seq Scan on customers
  -> Index Scan on orders
```
- For each outer row, scan inner table
- **Good** when: Inner table is small OR has index
- **Bad** when: Both tables are large with no index
- Watch for high `loops` count on inner scan

### Hash Join
```
Hash Join
  -> Seq Scan on customers (outer)
  -> Hash
       -> Seq Scan on orders (inner - builds hash)
```
- Builds hash table from one input, probes with other
- **Good** for medium-large tables without indexes
- Watch for `Batches > 1` (means spilled to disk)

### Merge Join
```
Merge Join
  -> Sort on customers
  -> Sort on orders
```
- Sorts both inputs, then merges
- **Good** when: Data is already sorted (from index)
- **Expensive** if sorts are required

---

## Red Flags to Watch For

### 1. Sequential Scan on Large Table
```
Seq Scan on orders (cost=0.00..15000.00 rows=500000)
  Filter: (status = 'pending')
  Rows Removed by Filter: 475000
```
**Problem**: Scanning 500K rows to find 25K
**Fix**: `CREATE INDEX ix_orders_status ON orders(status);`

### 2. High "Rows Removed by Filter"
```
Rows Removed by Filter: 99000
```
**Problem**: Reading far more rows than returned
**Fix**: Add index, rewrite as SARGable

### 3. Sort with High Cost
```
Sort (cost=50000.00..51000.00)
  Sort Key: order_date
  Sort Method: external merge  Disk: 50000kB
```
**Problem**: Sorting in memory or spilling to disk
**Fix**: Add index matching ORDER BY

### 4. Nested Loop with High Loops
```
Nested Loop (actual loops=100000)
  -> Seq Scan on customers
  -> Seq Scan on orders (actual loops=100000)
```
**Problem**: Inner scan runs 100K times
**Fix**: Add index on join column, or optimizer will switch to Hash Join

### 5. Hash Batches > 1
```
Hash (Batches=8)
```
**Problem**: Hash table didn't fit in work_mem, spilled to disk
**Fix**: Increase `work_mem` or reduce data with filters

---

## Good vs Bad Plans

### Bad Plan ❌
```
Nested Loop  (actual time=0.5..4523.2 rows=1000)
  -> Seq Scan on customers (rows=100000)
  -> Seq Scan on orders (loops=100000)
        Filter: (customer_id = customers.customer_id)
```
- 100K sequential scans of orders table!
- Total time: 4.5 seconds

### Good Plan ✅
```
Hash Join  (actual time=150.2..245.8 rows=1000)
  -> Seq Scan on customers (rows=100000)
  -> Hash
       -> Seq Scan on orders (rows=500000)
```
- Single scan of each table
- Total time: 0.25 seconds

### Better Plan ✅✅
```
Nested Loop  (actual time=0.1..12.5 rows=1000)
  -> Index Scan on customers using ix_state (rows=1000)
  -> Index Scan on orders using ix_customer_id (loops=1000)
```
- Index narrows customers to 1K rows
- Index lookup for each customer's orders
- Total time: 0.012 seconds

---

## Cost Estimation Factors

PostgreSQL's planner uses these settings:

| Parameter | Default | Meaning |
|-----------|---------|---------|
| `seq_page_cost` | 1.0 | Cost to read one page sequentially |
| `random_page_cost` | 4.0 | Cost to read one page randomly (index) |
| `cpu_tuple_cost` | 0.01 | Cost to process one row |
| `cpu_index_tuple_cost` | 0.005 | Cost to process one index entry |

**Key insight**: Random I/O is 4x more expensive than sequential. That's why sequential scans sometimes win for low-selectivity queries.

---

## Useful Settings for Analysis
```sql
-- See buffer usage (cache hits vs disk reads)
EXPLAIN (ANALYZE, BUFFERS) SELECT ...

-- Force specific behaviors (for testing only!)
SET enable_seqscan = off;  -- Force index usage
SET enable_hashjoin = off; -- Force nested loop

-- Increase memory for sorts and hashes
SET work_mem = '256MB';

-- Reset to defaults
RESET ALL;
```

---

## Quick Checklist

Before optimizing, check:

1. ✅ Is there a sequential scan on a large table?
2. ✅ Are there sorts that could be avoided with indexes?
3. ✅ Is "Rows Removed by Filter" very high?
4. ✅ Are there nested loops with high loop counts?
5. ✅ Are hash joins spilling to disk?
6. ✅ Is the actual row count close to estimated?

If estimates are way off, run `ANALYZE tablename;` to update statistics.

---

## Further Reading

- [PostgreSQL EXPLAIN Documentation](https://www.postgresql.org/docs/current/sql-explain.html)
- [Using EXPLAIN](https://www.postgresql.org/docs/current/using-explain.html)
- [explain.depesz.com](https://explain.depesz.com/) - Visual plan analyzer
