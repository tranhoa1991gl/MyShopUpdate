/*
    Bổ sung ghi chú/vị trí kệ cho từng lô hàng.
    Idempotent: có thể chạy lại an toàn trên dữ liệu hiện có.
*/
SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.product_batches', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.product_batches', N'note') IS NULL
BEGIN
    ALTER TABLE dbo.product_batches
    ADD note NVARCHAR(500) NOT NULL
        CONSTRAINT DF_product_batches_note DEFAULT (N'') WITH VALUES;
END;

COMMIT TRANSACTION;
