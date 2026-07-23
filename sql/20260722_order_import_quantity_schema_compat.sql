/* Hotfix 2026-07-22
   - Add quantity/unit compatibility columns that exist in fresh databases but may
     be missing on upgraded customer databases.
   - Must run before reports/procedures that reference order_items.base_quantity
     or import_details.base_quantity.

   Safe to run repeatedly on an existing customer database.
*/

IF COL_LENGTH(N'dbo.order_items', N'product_variant_id') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD product_variant_id INT NULL;
END
GO

IF COL_LENGTH(N'dbo.order_items', N'unit_id') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD unit_id INT NULL;
END
GO

IF COL_LENGTH(N'dbo.order_items', N'input_quantity') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD input_quantity DECIMAL(18,3) NULL;
END
GO

IF COL_LENGTH(N'dbo.order_items', N'base_quantity') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD base_quantity DECIMAL(18,3) NULL;
END
GO

IF COL_LENGTH(N'dbo.order_items', N'unit_conversion_to_base') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD unit_conversion_to_base DECIMAL(18,6) NULL;
END
GO

IF COL_LENGTH(N'dbo.order_items', N'variant_name_snapshot') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD variant_name_snapshot NVARCHAR(250) NULL;
END
GO

IF COL_LENGTH(N'dbo.order_items', N'unit_name_snapshot') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD unit_name_snapshot NVARCHAR(50) NULL;
END
GO

IF COL_LENGTH(N'dbo.order_items', N'stock_before') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD stock_before INT NULL;
END
GO

IF COL_LENGTH(N'dbo.order_items', N'stock_after') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD stock_after INT NULL;
END
GO

IF COL_LENGTH(N'dbo.order_items', N'gift_quantity') IS NULL
BEGIN
    ALTER TABLE dbo.order_items
    ADD gift_quantity INT NOT NULL
        CONSTRAINT DF_order_items_gift_quantity DEFAULT(0) WITH VALUES;
END
GO

UPDATE dbo.order_items
SET
    input_quantity = CASE
        WHEN input_quantity IS NULL THEN CAST(quantity AS DECIMAL(18,3))
        ELSE input_quantity
    END,
    base_quantity = CASE
        WHEN base_quantity IS NULL THEN
            CAST(
                CASE
                    WHEN ISNULL(quantity, 0) < 0 THEN ISNULL(quantity, 0) - ISNULL(gift_quantity, 0)
                    ELSE ISNULL(quantity, 0) + ISNULL(gift_quantity, 0)
                END
                AS DECIMAL(18,3)
            )
        ELSE base_quantity
    END,
    unit_conversion_to_base = CASE
        WHEN unit_conversion_to_base IS NULL THEN CAST(1 AS DECIMAL(18,6))
        ELSE unit_conversion_to_base
    END
WHERE input_quantity IS NULL
   OR base_quantity IS NULL
   OR unit_conversion_to_base IS NULL;
GO

IF COL_LENGTH(N'dbo.import_details', N'product_variant_id') IS NULL
BEGIN
    ALTER TABLE dbo.import_details ADD product_variant_id INT NULL;
END
GO

IF COL_LENGTH(N'dbo.import_details', N'unit_id') IS NULL
BEGIN
    ALTER TABLE dbo.import_details ADD unit_id INT NULL;
END
GO

IF COL_LENGTH(N'dbo.import_details', N'input_quantity') IS NULL
BEGIN
    ALTER TABLE dbo.import_details ADD input_quantity DECIMAL(18,3) NULL;
END
GO

IF COL_LENGTH(N'dbo.import_details', N'base_quantity') IS NULL
BEGIN
    ALTER TABLE dbo.import_details ADD base_quantity DECIMAL(18,3) NULL;
END
GO

IF COL_LENGTH(N'dbo.import_details', N'unit_conversion_to_base') IS NULL
BEGIN
    ALTER TABLE dbo.import_details ADD unit_conversion_to_base DECIMAL(18,6) NULL;
END
GO

IF COL_LENGTH(N'dbo.import_details', N'lot_code') IS NULL
BEGIN
    ALTER TABLE dbo.import_details ADD lot_code NVARCHAR(100) NULL;
END
GO

IF COL_LENGTH(N'dbo.import_details', N'manufacture_date') IS NULL
BEGIN
    ALTER TABLE dbo.import_details ADD manufacture_date DATE NULL;
END
GO

IF COL_LENGTH(N'dbo.import_details', N'expiry_date') IS NULL
BEGIN
    ALTER TABLE dbo.import_details ADD expiry_date DATE NULL;
END
GO

UPDATE dbo.import_details
SET
    input_quantity = CASE
        WHEN input_quantity IS NULL THEN CAST(quantity AS DECIMAL(18,3))
        ELSE input_quantity
    END,
    base_quantity = CASE
        WHEN base_quantity IS NULL THEN CAST(quantity AS DECIMAL(18,3))
        ELSE base_quantity
    END,
    unit_conversion_to_base = CASE
        WHEN unit_conversion_to_base IS NULL THEN CAST(1 AS DECIMAL(18,6))
        ELSE unit_conversion_to_base
    END
WHERE input_quantity IS NULL
   OR base_quantity IS NULL
   OR unit_conversion_to_base IS NULL;
GO
