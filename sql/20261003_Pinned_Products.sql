-- HoaTranPOS: quick access to pinned products. SQL Server / LocalDB.
-- Idempotent; existing products start unpinned. No stock or price changes.
SET XACT_ABORT ON;
BEGIN TRY
    BEGIN TRANSACTION;
    DECLARE @PinMigrationLock INT;
    EXEC @PinMigrationLock = sys.sp_getapplock
        @Resource=N'HoaTranPOS.PinnedProducts.Schema', @LockMode='Exclusive',
        @LockOwner='Transaction', @LockTimeout=15000;
    IF @PinMigrationLock < 0
        THROW 51000, N'Không thể khóa nâng cấp sản phẩm ghim.', 1;
    IF OBJECT_ID(N'dbo.products', N'U') IS NULL
        THROW 51000, N'Chưa có bảng hàng hóa để nâng cấp sản phẩm ghim.', 1;

    IF COL_LENGTH(N'dbo.products', N'is_pinned') IS NULL
        ALTER TABLE dbo.products ADD is_pinned BIT NOT NULL
            CONSTRAINT DF_products_is_pinned DEFAULT (0) WITH VALUES;

    IF NOT EXISTS (SELECT 1 FROM sys.indexes
                   WHERE object_id=OBJECT_ID(N'dbo.products') AND name=N'IX_products_pinned')
        -- Compile after adding the new column, including when run as one batch.
        EXEC sys.sp_executesql N'CREATE INDEX IX_products_pinned
            ON dbo.products(is_pinned, is_active, product_name, product_id)
            INCLUDE (category_id);';
    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
