# SQL Performance Optimization Lab

## 📋 Overview

A collection of before/after SQL optimization examples demonstrating query tuning techniques, indexing strategies, and performance analysis. Written in **PostgreSQL** with concepts applicable to any relational database.

---

## 🎯 Why This Matters

Writing functional SQL is easy. Writing *efficient* SQL at scale is what separates junior from senior engineers. This lab demonstrates:
- Understanding execution plans
- Index design decisions
- Query rewrite patterns
- Performance measurement methodology

---

## 🛠️ Technologies

- **PostgreSQL** (primary)
- Concepts apply to: SQL Server, MySQL, Snowflake, etc.

---

## 📊 Optimization Techniques Covered

| Technique | Typical Improvement | Use Case |
|-----------|---------------------|----------|
| Proper Indexing | 10-1000x | Large table scans |
| SARGable Predicates | 10-100x | WHERE clause optimization |
| Query Rewrites | 2-50x | Inefficient patterns |
| Join Optimization | 5-100x | Multi-table queries |
| Avoiding SELECT * | 2-10x | Unnecessary columns |

---

## 🔧 Quick Reference: Common Anti-Patterns

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| `WHERE EXTRACT(YEAR FROM date) = 2024` | Non-SARGable | `WHERE date >= '2024-01-01' AND date < '2025-01-01'` |
| `WHERE column + 1 = 5` | Non-SARGable | `WHERE column = 4` |
| `WHERE UPPER(col) = 'X'` | Non-SARGable | Use CITEXT type or expression index |
| `SELECT *` | Excess I/O | Specify needed columns |
| `OR` in WHERE | Poor index use | UNION ALL separate queries |

---

## 📈 Example: Before & After

### Problem: Slow Customer Search

**Before (Sequential Scan - 4.2 seconds):**
```sql
SELECT * 
FROM customers 
WHERE EXTRACT(YEAR FROM created_date) = 2024 
  AND UPPER(email) LIKE '%@GMAIL.COM';
```

**After (Index Scan - 0.02 seconds):**
```sql
SELECT customer_id, first_name, last_name, email, created_date
FROM customers 
WHERE created_date >= '2024-01-01' 
  AND created_date < '2025-01-01'
  AND email ILIKE '%@gmail.com';

-- With supporting index:
CREATE INDEX ix_customers_created ON customers(created_date);
```

**Why it's faster:**
1. Removed function on `created_date` (now SARGable)
2. Avoided `SELECT *` (reduced I/O)
3. Added supporting index
4. Used ILIKE instead of UPPER() for case-insensitive search

---

## 🚀 How to Use This Lab

1. Run `01_setup_test_tables.sql` to create tables with sample data
2. Enable timing: `\timing on` in psql
3. Run "Before" query and note the time
4. Run "After" query and compare
5. Use `EXPLAIN ANALYZE` to see execution plans
```sql
-- See what PostgreSQL is doing
EXPLAIN ANALYZE
SELECT * FROM customers WHERE created_date >= '2024-01-01';
```

---

## 📁 Files

| File | Description |
|------|-------------|
| `sql/01_setup_test_tables.sql` | Creates tables with sample data |
| `sql/02_indexing_examples.sql` | Index creation and optimization |
| `sql/03_sargable_queries.sql` | SARGable vs non-SARGable comparisons |
| `sql/04_join_optimization.sql` | Join strategy optimization |
| `sql/05_query_rewrites.sql` | Common anti-patterns fixed |
| `docs/execution_plan_guide.md` | How to read EXPLAIN output |

---

## 💡 Key Concepts

### SARGable (Search ARGument ABLE)
A predicate is SARGable if PostgreSQL can use an index seek instead of a scan. Functions on columns typically break SARGability.

### Covering Index
An index that includes all columns needed by a query via `INCLUDE`, eliminating the need to access the heap.

### Index-Only Scan
When PostgreSQL can satisfy the entire query from the index without touching the table.

---

## 🎓 Key Learnings

- Always check execution plans before and after optimization
- Index design should be driven by query patterns
- Small changes (SARGability) can yield massive improvements
- Measure with realistic data volumes
