SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF COL_LENGTH(N'dbo.products', N'has_batch_expiry') IS NULL
    ALTER TABLE dbo.products
    ADD has_batch_expiry BIT NOT NULL
        CONSTRAINT DF_products_has_batch_expiry DEFAULT (0) WITH VALUES;

IF EXISTS
(
    SELECT 1
    FROM dbo.products
    WHERE ISNULL(has_serial, 0) = 1
      AND ISNULL(has_batch_expiry, 0) = 1
)
    THROW 51120, N'Không thể áp dụng quy tắc: đang có sản phẩm bật đồng thời IMEI/Serial và Lô/HSD.', 1;

IF OBJECT_ID(N'dbo.CK_products_tracking_mode_exclusive', N'C') IS NULL
    ALTER TABLE dbo.products WITH CHECK
    ADD CONSTRAINT CK_products_tracking_mode_exclusive
        CHECK (NOT (ISNULL(has_serial, 0) = 1 AND ISNULL(has_batch_expiry, 0) = 1));

COMMIT TRANSACTION;
