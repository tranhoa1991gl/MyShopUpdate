SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @LockResult INT;
EXEC @LockResult = sys.sp_getapplock @Resource=N'HoaTranPOS.PurchaseLineDiscount',
    @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=15000;
IF @LockResult < 0
    THROW 51001, N'Không thể khóa cập nhật cấu trúc giảm giá dòng.', 1;

IF COL_LENGTH(N'dbo.import_details', N'discount') IS NULL
    ALTER TABLE dbo.import_details ADD discount DECIMAL(18,2) NOT NULL
        CONSTRAINT DF_import_details_discount DEFAULT (0) WITH VALUES;

IF COL_LENGTH(N'dbo.import_details', N'discount_percent') IS NULL
    ALTER TABLE dbo.import_details ADD discount_percent DECIMAL(5,2) NOT NULL
        CONSTRAINT DF_import_details_discount_percent DEFAULT (0) WITH VALUES;

COMMIT TRANSACTION;
