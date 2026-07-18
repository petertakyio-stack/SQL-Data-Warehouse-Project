/*
=======================================================================================
Stored Procedure: Bulk load of data into the database from the sources
=======================================================================================
Script Purpose:
    This stored Procedure loads data into 'bronze' schema from external CSV files.
    It performs the following actions:
    - Truncates the bronze tables before loading the data
    - Uses the 'BULK INSERT' command to load data from csv files to bronze tables.

=============================
NOTE: MACBOOK USERS
=============================
Note that on a Macbook, the SQL Server cannot directly access the files on the local machine. The files must be copied to the /tmp directory in order for the SQL Server to access them. This is because the SQL Server is running in a Docker container, which has its own file system that is separate from the host machine's file system. The /tmp directory is a shared directory between the host machine and the Docker container, so it can be used to transfer files between the two environments.
You can use terminal to copy files from the local machine to the /tmp directory in the Docker container. For example, you can use the following command to copy a file named "cust_info.csv" from the local machine to the /tmp directory in the Docker container:
cp /path/to/cust_info.csv /tmp/cust_info.csv

Also note that for bulk load on macbook, the data type cannot be date or datetime or any other related data type. The data type must be NVARCHAR or VARCHAR. This is because the SQL Server on Macbook does not support the date and datetime data types for bulk load. Therefore, you will need to change the data type of the columns in the source files to NVARCHAR or VARCHAR before performing the bulk load. Do this load to a stage table and then convert the data type to date or datetime in the final table. This is a workaround for the limitation of the SQL Server on Macbook.

-- 1. Drop the staging table if it already exists
DROP TABLE IF EXISTS #stg_cust_info;

-- 2. Create the staging table with VARCHAR for the date
CREATE TABLE #stg_cust_info (
    cst_id INT,
    cst_key VARCHAR(50),
    cst_firstname VARCHAR(100),
    cst_lastname VARCHAR(100),
    cst_marital_status VARCHAR(50),
    cst_gndr VARCHAR(50),
    cst_create_date VARCHAR(50) -- Kept as text to prevent conversion errors
);

Now, run the bulk insert command into this text-based staging table. It will succeed because SQL Server won't try to validate the date format yet.

BULK INSERT #stg_cust_info
FROM '/tmp/cust_info.csv'
WITH (
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '0x0a',
    FIRSTROW = 2
);

Now you can safely move the data from your staging table into your real, permanent cust_info table. SQL Server will automatically parse standard date strings (like YYYY-MM-DD) during a direct INSERT INTO statement.

-- Clear out old failed attempts from your final table first
TRUNCATE TABLE bronze.crm_cust_info;

-- Insert into your final table
INSERT INTO bronze.crm_cust_info (cst_id, cst_key, cst_firstname, cst_lastname, cst_marital_status, cst_gndr, cst_create_date)
SELECT 
    cst_id, 
    cst_key, 
    cst_firstname, 
    cst_lastname, 
    cst_marital_status, 
    cst_gndr,
    -- TRIM removes hidden spaces/breaks; 102 forces ANSI YYYY-MM-DD format
    TRY_CONVERT(DATE, NULLIF(REPLACE(REPLACE(TRIM(cst_create_date), CHAR(13), ''), CHAR(10), ''), ''), 102) 
FROM #stg_cust_info;

ALTER TABLE bronze.crm_cust_info ALTER COLUMN cst_create_date DATE;


You can create a stored procedure since it will be run countless time. Note that after creating the stored procedure on a macbook with the code below, it wont work until you apply the above script for all the data containing DATE or DATETIME format first
*/

CREATE OR ALTER PROCEDURE bronze.load_bronze AS
BEGIN
    DECLARE @start_time DATETIME, @end_time DATETIME, @batch_start_time DATETIME, @batch_end_time DATETIME; 
    BEGIN TRY
		SET @batch_start_time = GETDATE();
        PRINT '================================';
        PRINT 'Load Bronze Layer';
        PRINT '================================';


        PRINT '--------------------------------';
        PRINT 'Loading CRM Tables';
        PRINT '--------------------------------';
        
        SET @start_time = GETDATE();       
        PRINT '>> Truncating Table crm_cust_info';
        TRUNCATE TABLE bronze.crm_cust_info;
        
        PRINT '>> Loading CRM Customer Info';
        BULK INSERT bronze.crm_cust_info
        FROM '/tmp/cust_info.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
		SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @start_time = GETDATE();
        PRINT '>> Truncating Table crm_prd_info';
        TRUNCATE TABLE bronze.crm_prd_info;

        PRINT '>> Loading CRM Product Info';
        BULK INSERT bronze.crm_prd_info
        FROM '/tmp/prd_info.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
		SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @start_time = GETDATE();
        PRINT '>> Truncating Table crm_sales_details';
        TRUNCATE TABLE bronze.crm_sales_details;

        PRINT '>> Loading CRM Sales Details';
        BULK INSERT bronze.crm_sales_details
        FROM '/tmp/sales_details.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
		SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        PRINT '--------------------------------';
        PRINT 'Loading ERP Tables';
        PRINT '--------------------------------';

        SET @start_time = GETDATE();
        PRINT '>> Truncating Table erp_cust_az12';
        TRUNCATE TABLE bronze.erp_cust_az12;
        
        PRINT '>> Loading ERP Customer Info';
        BULK INSERT bronze.erp_cust_az12
        FROM '/tmp/cust_az12.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
		SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @start_time = GETDATE();
        PRINT '>> Truncating Table erp_loc_a101';
        TRUNCATE TABLE bronze.erp_loc_a101;
        
        PRINT '>> Loading ERP Location Info';
        BULK INSERT bronze.erp_loc_a101
        FROM '/tmp/loc_a101.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
		SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

        SET @start_time = GETDATE();
        PRINT '>> Truncating Table erp_px_cat_g1v2';
        TRUNCATE TABLE bronze.erp_px_cat_g1v2;

        PRINT '>> Loading ERP Product Category Info';
        BULK INSERT bronze.erp_px_cat_g1v2
        FROM '/tmp/px_cat_g1v2.csv'
        WITH (
            FIRSTROW = 2,
            FIELDTERMINATOR = ',',
            TABLOCK
        );
		SET @end_time = GETDATE();
        PRINT '>> Load Duration: ' + CAST(DATEDIFF(SECOND, @start_time, @end_time) AS NVARCHAR) + ' seconds';
        PRINT '>> -------------';

		SET @batch_end_time = GETDATE();
		PRINT '=========================================='
		PRINT 'Loading Bronze Layer is Completed';
        PRINT '   - Total Load Duration: ' + CAST(DATEDIFF(SECOND, @batch_start_time, @batch_end_time) AS NVARCHAR) + ' seconds';
		PRINT '=========================================='

    END TRY
    BEGIN CATCH
        PRINT 'Error occurred while loading bronze layer: ' + ERROR_MESSAGE();
    END CATCH
END

EXEC bronze.load_bronze;

