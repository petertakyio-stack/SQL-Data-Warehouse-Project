/*
==================================================================
Stored Procedure: Load Data to Silver Layer (Bronze - -> Silver)
==================================================================
Script Purpose: 
  This stored procedure performs the ETL (Extract, Transform, Load) process 
  on the bronze schema layer to populate the silver layer schema tables.

Actions Performed:
  - Truncates Silver tables
  - Inserts transformed and cleansed data from the bronze into silver tables.

Parameters:
  - None
  This stored procedure does not accept any parameters or return any values
*/

-- ===========================================================
-- LOADING DATA TO SILVER LAYER AND CREATING STORED PROCEDURE
-- ============================================================

CREATE OR ALTER PROCEDURE silver.load_silver AS
BEGIN
    DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME; 
    BEGIN TRY
        SET @batch_start_time = GETDATE();
        PRINT '================================================';
        PRINT 'Loading Silver Layer';
        PRINT '================================================';

		PRINT '------------------------------------------------';
		PRINT 'Loading CRM Tables';
		PRINT '------------------------------------------------';
        -- =========================================
        -- INSERT INTO SILVER LAYER (crm_cust_info)
        -- =========================================

        SET @start_time = GETDATE();
        PRINT '>>> Truncating Table silver.crm_cust_info';
        TRUNCATE TABLE silver.crm_cust_info;

        PRINT '>>> Inserting Data into Table silver.crm_cust_info';
        INSERT INTO silver.crm_cust_info (
                    cst_id,
                    cst_key,
                    cst_firstname,
                    cst_lastname,
                    cst_marital_status,
                    cst_gndr,
                    cst_create_date
                )
        SELECT 
            cst_id, 
            cst_key, 
            TRIM (cst_firstname) AS cst_firstname, -- Trim leading and trailing spaces from the cst_firstname column
            TRIM (cst_lastname) AS cst_lastname, -- Trim leading and trailing spaces from the cst_lastname column
            CASE
            WHEN UPPER(TRIM(cst_marital_status)) = 'M' THEN 'Married'
            WHEN UPPER(TRIM(cst_marital_status)) = 'S' THEN 'Single'
            ELSE 'N/A' -- Handling missing data by assigning 'N/A' for any other values in the cst_marital_status column
            END AS cst_marital_status, -- Normalise the marital status column to make it more readable
            CASE 
                WHEN UPPER(TRIM(cst_gndr)) = 'M' THEN 'Male'
                WHEN UPPER(TRIM(cst_gndr)) = 'F' THEN 'Female'
                ELSE 'N/A' -- Handling missing data by assigning 'N/A'
            END AS cst_gndr, -- Normalise the gender column to make it more readable
            cst_create_date
        FROM (
            SELECT
                *,
                ROW_NUMBER() OVER (PARTITION BY cst_id ORDER BY cst_create_date DESC) AS flag_last
            FROM bronze.crm_cust_info
            WHERE cst_id IS NOT NULL -- Remove duplicates
        )t
        WHERE flag_last = 1; -- Filter data to select the most recent record based on the cst_create_date column.
		SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        -- =========================================
        -- INSERT INTO SILVER LAYER (crm_cust_info)
        -- =========================================
        SET @start_time = GETDATE();
        PRINT '>>> Truncating Table silver.crm_prd_info';
        TRUNCATE TABLE silver.crm_prd_info;

        PRINT '>>> Inserting Data into Table silver.crm_prd_info';
        INSERT INTO silver.crm_prd_info (
                    prd_id,
                    cat_id,
                    prd_key,
                    prd_nm,
                    prd_cost,
                    prd_line,
                    prd_start_dt,
                    prd_end_dt
                )
        SELECT 
            prd_id,
            REPLACE(SUBSTRING(prd_key, 1,5), '-', '_') AS cat_id, -- From this column the category id can be extracted from the product key to match with bronze.erp_px_cat_g1v2 table
            SUBSTRING(prd_key,7, LEN(prd_key)) AS prd_key, -- From this column the prd_key can be put in the same format as bronze.crm_sales_details table
            prd_nm,
            COALESCE(prd_cost,0) AS prd_cost, -- Handling nulls and converting them to zero
            CASE UPPER(TRIM(prd_line))
                WHEN 'M' THEN 'Mountain'
                WHEN 'R' THEN 'Road'
                WHEN 'S' THEN 'Other Sales'
                WHEN 'T' THEN 'Touring'
                ELSE 'N/A'
            END AS prd_line, -- Data standardisation and handling nulls
            CAST (prd_start_dt AS DATE) AS prd_start_dt, -- changed date format to date since there are no time values
            CAST(DATEADD(day, -1, LEAD(prd_start_dt) OVER (PARTITION BY prd_key ORDER BY prd_start_dt)) AS DATE) AS prd_end_dt -- Data enrichment: New column to correct errors in end date
        FROM bronze.crm_prd_info;
		SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';


        -- ==============================================
        -- INSERT INTO SILVER LAYER (crm_sales_details)
        -- ==============================================

        SET @start_time = GETDATE();
        PRINT '>>> Truncating Table silver.crm_sales_details';
        TRUNCATE TABLE silver.crm_sales_details;

        PRINT '>>> Inserting Data into Table silver.crm_sales_details';
        INSERT INTO silver.crm_sales_details (
                    sls_ord_num,
                    sls_prd_key,
                    sls_cust_id,
                    sls_order_dt,
                    sls_ship_dt,
                    sls_due_dt,
                    sls_sales,
                    sls_quantity,
                    sls_price
                )  
        SELECT
            sls_ord_num,
            sls_prd_key,
            sls_cust_id,
            CASE WHEN
                sls_order_dt = 0 OR LEN(sls_order_dt) != 8 THEN NULL 
                ELSE CAST(CAST(sls_order_dt AS VARCHAR) AS DATE) -- since you cannot cast directly from INT to DATE
            END sls_order_dt,
            CASE WHEN
                sls_ship_dt = 0 OR LEN(sls_ship_dt) != 8 THEN NULL 
                ELSE CAST(CAST(sls_ship_dt AS VARCHAR) AS DATE) -- since you cannot cast directly from INT to DATE
            END sls_ship_dt,
                CASE WHEN
                sls_due_dt = 0 OR LEN(sls_due_dt) != 8 THEN NULL 
                ELSE CAST(CAST(sls_due_dt AS VARCHAR) AS DATE) -- since you cannot cast directly from INT to DATE
            END sls_due_dt,
            CASE WHEN sls_sales IS NULL OR sls_sales <= 0 OR sls_sales != sls_quantity * ABS (sls_price) THEN sls_quantity * ABS(sls_price)
                ELSE sls_sales
            END AS sls_sales,
            sls_quantity,
            CASE WHEN sls_price IS NULL OR sls_price <= 0 THEN sls_sales / NULLIF(sls_quantity,0) -- To avoid division by zero in the future
                ELSE sls_price
            END AS sls_price
        FROM bronze.crm_sales_details;       
		SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        PRINT '------------------------------------------------';
		PRINT 'Loading ERP Tables';
		PRINT '------------------------------------------------';
        -- ==============================================
        -- INSERT INTO SILVER LAYER (erp_cust_az12)
        -- ==============================================

        SET @start_time = GETDATE();
        PRINT '>>> Truncating Table silver.erp_cust_az12';
        TRUNCATE TABLE silver.erp_cust_az12;

        PRINT '>>> Inserting Data into Table silver.erp_cust_az12';
        INSERT INTO silver.erp_cust_az12 (cid,bdate,gen)
        SELECT
            CASE WHEN cid LIKE 'NAS%' THEN SUBSTRING(cid,4,LEN(cid)) -- This extracts everything after NAS for rows that have it
                ELSE cid
            END AS cid,
            CASE WHEN bdate > GETDATE() THEN NULL -- Gets rid of birthdates in the future
                ELSE bdate
            END AS bdate,
            CASE 
                WHEN UPPER(TRIM(REPLACE(REPLACE(gen, CHAR(13), ''), CHAR(10), ''))) IN ('F', 'FEMALE') THEN 'Female'
                WHEN UPPER(TRIM(REPLACE(REPLACE(gen, CHAR(13), ''), CHAR(10), ''))) IN ('M', 'MALE') THEN 'Male'
                ELSE 'N/A'
            END AS gen
        FROM bronze.erp_cust_az12;
		SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';


        -- ==============================================
        -- INSERT INTO SILVER LAYER (erp_loc_a101)
        -- ==============================================

        SET @start_time = GETDATE();
        PRINT '>>> Truncating Table silver.erp_loc_a101';
        TRUNCATE TABLE silver.erp_loc_a101;

        PRINT '>>> Inserting Data into Table silver.erp_loc_a101';
        INSERT INTO silver.erp_loc_a101 (cid, cntry)
        SELECT
                REPLACE (cid, '-', '') AS cid,    
            CASE  -- Clean line breaks, strip spaces, and uppercase for robust matching. Data Standardisation
                WHEN UPPER(TRIM(REPLACE(REPLACE(cntry, CHAR(13), ''), CHAR(10), ''))) IN ('DE', 'GERMANY') THEN 'Germany'
                WHEN UPPER(TRIM(REPLACE(REPLACE(cntry, CHAR(13), ''), CHAR(10), ''))) IN ('US', 'USA', 'UNITED STATES') THEN 'United States'
                WHEN TRIM(REPLACE(REPLACE(ISNULL(cntry, ''), CHAR(13), ''), CHAR(10), '')) = '' THEN 'N/A'
                ELSE TRIM(REPLACE(REPLACE(cntry, CHAR(13), ''), CHAR(10), ''))
            END AS cntry
        FROM bronze.erp_loc_a101;
		SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';


        -- ==============================================
        -- INSERT INTO SILVER LAYER (px_cat_g1v2)
        -- ==============================================
        SET @start_time = GETDATE();
        PRINT '>>> Truncating Table silver.erp_px_cat_g1v2';
        TRUNCATE TABLE silver.erp_px_cat_g1v2;

        PRINT '>>> Inserting Data into Table silver.erp_px_cat_g1v2';
        INSERT INTO silver.erp_px_cat_g1v2(id,cat,sub_cat,maintenance)
        SELECT
            id,
            cat,
            sub_cat,
            TRIM(REPLACE(REPLACE(maintenance, CHAR(13), ''), CHAR(10), '')) AS maintenance -- Clean line breaks, strip spaces, and uppercase for robust matching
        FROM bronze.erp_px_cat_g1v2;
		SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

		SET @batch_end_time = GETDATE();
		PRINT '=========================================='
		PRINT 'Loading Silver Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
		PRINT '=========================================='

    END TRY
	BEGIN CATCH
		PRINT '=========================================='
		PRINT 'ERROR OCCURED DURING LOADING SILVER LAYER'
		PRINT 'Error Message' + ERROR_MESSAGE();
		PRINT 'Error Message' + CAST (ERROR_NUMBER() AS NVARCHAR);
		PRINT 'Error Message' + CAST (ERROR_STATE() AS NVARCHAR);
		PRINT '=========================================='
	END CATCH
END

EXEC silver.load_silver


