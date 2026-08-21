SET XACT_ABORT ON;
BEGIN TRANSACTION;

/*
   Gắn từng dòng phiếu nhập với biến thể Màu/Size tương ứng.
   Dữ liệu phiếu nhập cũ giữ variant_id = NULL và hoạt động như trước.
*/
IF OBJECT_ID(N'dbo.import_details', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.product_variants', N'U') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'dbo.import_details', N'variant_id') IS NULL
        ALTER TABLE dbo.import_details ADD variant_id INT NULL;

    IF NOT EXISTS
    (
        SELECT 1 FROM sys.foreign_keys
        WHERE parent_object_id = OBJECT_ID(N'dbo.import_details')
          AND referenced_object_id = OBJECT_ID(N'dbo.product_variants')
          AND name = N'FK_import_details_product_variants'
    )
        ALTER TABLE dbo.import_details WITH CHECK
        ADD CONSTRAINT FK_import_details_product_variants
            FOREIGN KEY(variant_id) REFERENCES dbo.product_variants(variant_id);

    IF NOT EXISTS
    (
        SELECT 1 FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.import_details')
          AND name = N'IX_import_details_variant_id'
    )
        CREATE INDEX IX_import_details_variant_id ON dbo.import_details(variant_id);
END;

COMMIT TRANSACTION;
