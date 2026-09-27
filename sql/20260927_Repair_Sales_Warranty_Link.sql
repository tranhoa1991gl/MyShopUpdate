-- Additive upgrade. Existing repair orders and sales remain unchanged.
-- The desktop also applies these columns on first use for offline installations.
SET NOCOUNT ON;
SET XACT_ABORT ON;
IF OBJECT_ID(N'dbo.repair_orders',N'U') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'dbo.repair_orders',N'warranty_source_order_id') IS NULL
        ALTER TABLE dbo.repair_orders ADD warranty_source_order_id INT NULL;
    IF COL_LENGTH(N'dbo.repair_orders',N'warranty_source_order_item_id') IS NULL
        ALTER TABLE dbo.repair_orders ADD warranty_source_order_item_id INT NULL;
    IF COL_LENGTH(N'dbo.repair_orders',N'warranty_source_order_code') IS NULL
        ALTER TABLE dbo.repair_orders ADD warranty_source_order_code NVARCHAR(50) NULL;
    IF COL_LENGTH(N'dbo.repair_orders',N'warranty_source_product') IS NULL
        ALTER TABLE dbo.repair_orders ADD warranty_source_product NVARCHAR(500) NULL;
    IF COL_LENGTH(N'dbo.repair_orders',N'warranty_source_serial') IS NULL
        ALTER TABLE dbo.repair_orders ADD warranty_source_serial NVARCHAR(100) NULL;
    IF NOT EXISTS(SELECT 1 FROM sys.indexes WHERE object_id=OBJECT_ID(N'dbo.repair_orders') AND name=N'IX_repair_orders_sales_warranty')
        EXEC(N'CREATE INDEX IX_repair_orders_sales_warranty ON dbo.repair_orders(warranty_source_order_id,warranty_source_order_item_id);');
END;
