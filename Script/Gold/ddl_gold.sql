-- ================================
-- GOLD LAYER
--=================================

/*
===============================================================================
DDL Script: Create Gold Views
===============================================================================
Script Purpose:
    This script creates views for the Gold layer in the data warehouse. 
    The Gold layer represents the final dimension and fact tables (Star Schema)

    Each view performs transformations and combines data from the Silver layer 
    to produce a clean, enriched, and business-ready dataset.

Usage:
    - These views can be queried directly for analytics and reporting.
===============================================================================
*/

/* 
======================
GENERAL NOTES
======================
 After joining tables, check if any duplicates were introduced by the join logic. The select statement as comment at the start was used
-- Data integration for gender column resulting in new column new_gen
-- Remember to use FRIENDLY names as Aliases for the gold layer. Note: we adopted the snake case

-- Finally ask yourself if it is a dimension or fact table.



-- All dimensions need primary keys. When the data does not have primary keys you can rely on, generate a new primary key called surrogate keys
-- You can generate your surrogate key either via DDL or query based (window function - Row_Number)
*/

-- =============================================================================
-- Create Dimension: gold.dim_customers
-- =============================================================================

IF OBJECT_ID('gold.dim_customers', 'V') IS NOT NULL
    DROP VIEW gold.dim_customers;
GO

CREATE VIEW gold.dim_customers AS
SELECT
    ROW_NUMBER () OVER (ORDER BY cst_id) AS customer_key, -- newly generated surrogate key
    ci.cst_id AS customer_id,
    ci.cst_key AS customer_number,
    ci.cst_firstname AS first_name,
    ci.cst_lastname AS last_name,
    cl.cntry AS country,
    ci.cst_marital_status AS marital_status,
    CASE 
        WHEN ci.cst_gndr != 'N/A' THEN ci.cst_gndr -- CRM is the master for gender info
        ELSE COALESCE(cb.gen, 'N/A')
    END AS gender,
    cb.bdate AS birthdate,
    ci.cst_create_date AS create_date
FROM silver.crm_cust_info ci -- 'C'ustomer 'I'nformation (ci) as Alias
LEFT JOIN silver.erp_cust_az12 cb -- 'C'ustomer 'B'irthdate
ON        ci.cst_key = cb.cid
LEFT JOIN silver.erp_loc_a101 cl -- 'C'ustomer 'L'ocation
ON        ci.cst_key = cl.cid
GO

-- It is a dimension because it holds descriptive information about an object (customer).
-- Create surrogate key: customer_key
SELECT * FROM gold.dim_customers;

-- =============================================================================
-- Create Dimension: gold.dim_products
-- =============================================================================

IF OBJECT_ID('gold.dim_products', 'V') IS NOT NULL
    DROP VIEW gold.dim_products;
GO

CREATE VIEW gold.dim_products AS
SELECT
    ROW_NUMBER () OVER (ORDER BY pn.prd_start_dt, pn.prd_key) AS product_key,
    pn.prd_id AS product_id,
    pn.prd_key AS product_number,
    pn.prd_nm AS product_name,
    pn.cat_id AS category_id,
    pc.cat AS category,
    pc.sub_cat AS subcategory,
    pc.maintenance,
    pn.prd_cost AS cost,
    pn.prd_line AS product_line,
    pn.prd_start_dt AS start_date
FROM silver.crm_prd_info AS pn
LEFT JOIN silver.erp_px_cat_g1v2 pc
ON pn.cat_id = pc.id
WHERE prd_end_dt IS NULL -- filter out historical data and stay with current data
GO
-- Check for duplicates
-- There are no duplicates

-- It is a dimension because it holds descriptive information about an object (product).
-- create a surrogate key: product_key
SELECT * FROM gold.dim_products;
GO


-- =============================================================================
-- Create Dimension: gold.dim_sales
-- =============================================================================

IF OBJECT_ID('gold.fact_sales', 'V') IS NOT NULL
    DROP VIEW gold.fact_sales;

CREATE VIEW gold.fact_sales AS
SELECT 
    sd.sls_ord_num AS order_number,
    pr.product_key,
    cu.customer_key,
    sd.sls_order_dt AS order_date,
    sd.sls_ship_dt AS shipping_date,
    sd.sls_due_dt AS due_date,
    sd.sls_quantity AS quantity,
    sd.sls_price AS price,
    sd.sls_sales AS sales_amount
FROM silver.crm_sales_details sd
LEFT JOIN gold.dim_products pr
ON sd.sls_prd_key = pr.product_number
LEFT JOIN gold.dim_customers cu
ON sd.sls_cust_id = cu.customer_id
GO
-- This is a fact table since it connects multiple dimensions, hence include surrogate keys
-- Replace the connecting rows with the surrogate keys. eg replace cst_id with customer_key and prd_key with product_key
