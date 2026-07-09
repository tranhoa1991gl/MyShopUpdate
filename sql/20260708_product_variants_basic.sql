IF OBJECT_ID(N'dbo.product_variants', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.product_variants
    (
        variant_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_product_variants PRIMARY KEY,
        product_id INT NOT NULL,
        sku_code NVARCHAR(80) NOT NULL,
        variant_name NVARCHAR(250) NULL,
        size_value NVARCHAR(100) NULL,
        color_value NVARCHAR(100) NULL,
        barcode NVARCHAR(100) NULL,
        base_unit_id INT NULL,
        stock_base_qty DECIMAL(18,3) NOT NULL CONSTRAINT DF_product_variants_stock_base_qty DEFAULT (0),
        sell_price DECIMAL(18,2) NULL,
        import_price DECIMAL(18,2) NULL,
        is_default BIT NOT NULL CONSTRAINT DF_product_variants_is_default DEFAULT (0),
        is_active BIT NOT NULL CONSTRAINT DF_product_variants_is_active DEFAULT (1),
        created_at DATETIME NOT NULL CONSTRAINT DF_product_variants_created_at DEFAULT (GETDATE()),
        updated_at DATETIME NULL
    );

    CREATE UNIQUE INDEX UQ_product_variants_sku_code ON dbo.product_variants(sku_code);
END;

IF OBJECT_ID(N'dbo.product_variant_attributes', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.product_variant_attributes
    (
        attribute_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_product_variant_attributes PRIMARY KEY,
        variant_id INT NOT NULL,
        attribute_name NVARCHAR(100) NOT NULL,
        attribute_value NVARCHAR(200) NOT NULL,
        sort_order INT NOT NULL CONSTRAINT DF_product_variant_attributes_sort DEFAULT (0)
    );
END;

IF COL_LENGTH(N'dbo.order_items', N'product_variant_id') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD product_variant_id INT NULL;
END;

IF COL_LENGTH(N'dbo.order_items', N'variant_name_snapshot') IS NULL
BEGIN
    ALTER TABLE dbo.order_items ADD variant_name_snapshot NVARCHAR(250) NULL;
END;
