SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

IF COL_LENGTH(N'dbo.purchase_return_details', N'unit_id') IS NULL
    ALTER TABLE dbo.purchase_return_details ADD unit_id INT NULL;
IF COL_LENGTH(N'dbo.purchase_return_details', N'input_quantity') IS NULL
    ALTER TABLE dbo.purchase_return_details ADD input_quantity DECIMAL(18,3) NULL;
IF COL_LENGTH(N'dbo.purchase_return_details', N'base_quantity') IS NULL
    ALTER TABLE dbo.purchase_return_details ADD base_quantity DECIMAL(18,3) NULL;
IF COL_LENGTH(N'dbo.purchase_return_details', N'unit_conversion_to_base') IS NULL
    ALTER TABLE dbo.purchase_return_details ADD unit_conversion_to_base DECIMAL(18,6) NULL;
IF COL_LENGTH(N'dbo.purchase_return_details', N'unit_name_snapshot') IS NULL
    ALTER TABLE dbo.purchase_return_details ADD unit_name_snapshot NVARCHAR(50) NULL;

-- Dùng dynamic SQL để câu UPDATE chỉ được biên dịch sau khi các cột mới đã tồn tại.
EXEC sys.sp_executesql N'
UPDATE prd
SET unit_id = ISNULL(prd.unit_id, ISNULL(id.unit_id, p.unit_id)),
    input_quantity = ISNULL(prd.input_quantity, CAST(prd.quantity AS DECIMAL(18,3))),
    unit_conversion_to_base = ISNULL(prd.unit_conversion_to_base, ISNULL(NULLIF(id.unit_conversion_to_base, 0), 1)),
    base_quantity = ISNULL(prd.base_quantity,
        CAST(prd.quantity AS DECIMAL(18,3)) * ISNULL(NULLIF(id.unit_conversion_to_base, 0), 1)),
    unit_name_snapshot = ISNULL(NULLIF(prd.unit_name_snapshot, N''''), u.unit_name)
FROM dbo.purchase_return_details prd
LEFT JOIN dbo.import_details id ON id.import_detail_id = prd.import_detail_id
LEFT JOIN dbo.products p ON p.product_id = prd.product_id
LEFT JOIN dbo.Units u ON u.unit_id = ISNULL(id.unit_id, p.unit_id)
WHERE prd.unit_id IS NULL OR prd.input_quantity IS NULL OR prd.base_quantity IS NULL
   OR prd.unit_conversion_to_base IS NULL OR NULLIF(prd.unit_name_snapshot, N'''') IS NULL;';

COMMIT TRANSACTION;
