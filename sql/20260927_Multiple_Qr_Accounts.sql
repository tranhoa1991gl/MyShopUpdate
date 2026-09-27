-- HoaTranPOS: multiple receiving accounts and immutable sale payment snapshots.
-- Safe to run repeatedly. Existing StoreInfo bank fields remain the default account.
SET XACT_ABORT ON;
BEGIN TRANSACTION;
DECLARE @QrMigrationLock INT;
EXEC @QrMigrationLock = sys.sp_getapplock @Resource=N'HoaTranPOS.MultipleQrAccounts.Schema', @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=15000;
IF @QrMigrationLock < 0 THROW 51000, N'Không thể khóa nâng cấp tài khoản QR.', 1;
IF OBJECT_ID(N'dbo.QrReceivingAccount', N'U') IS NULL
BEGIN
 CREATE TABLE dbo.QrReceivingAccount (
  AccountId INT IDENTITY PRIMARY KEY,
  DisplayName NVARCHAR(100) NOT NULL,
  BankCode NVARCHAR(50) NOT NULL,
  AccountNumber NVARCHAR(50) NOT NULL,
  AccountOwner NVARCHAR(150) NOT NULL,
  IsActive BIT NOT NULL DEFAULT 1,
  IsDefault BIT NOT NULL DEFAULT 0,
  AutoConfirm BIT NOT NULL DEFAULT 0,
  CONSTRAINT UQ_QrReceivingAccount UNIQUE (BankCode, AccountNumber)
 );
 CREATE UNIQUE INDEX UX_QrReceivingAccount_Default ON dbo.QrReceivingAccount(IsDefault) WHERE IsDefault = 1;
END;
IF OBJECT_ID(N'dbo.QrPaymentConfig', N'U') IS NULL
 CREATE TABLE dbo.QrPaymentConfig (Id INT PRIMARY KEY CHECK (Id = 1), AllowSelection BIT NOT NULL DEFAULT 0);
IF NOT EXISTS (SELECT 1 FROM dbo.QrPaymentConfig WHERE Id = 1)
 INSERT dbo.QrPaymentConfig VALUES (1, 0);
IF NOT EXISTS (SELECT 1 FROM dbo.QrReceivingAccount)
 INSERT dbo.QrReceivingAccount(DisplayName,BankCode,AccountNumber,AccountOwner,IsDefault)
 SELECT TOP 1 N'Tài khoản cửa hàng', LTRIM(RTRIM(bank_name)), LTRIM(RTRIM(bank_account)), ISNULL(bank_owner,N''), 1
 FROM dbo.StoreInfo WHERE NULLIF(LTRIM(RTRIM(bank_name)),N'') IS NOT NULL AND NULLIF(LTRIM(RTRIM(bank_account)),N'') IS NOT NULL
 ORDER BY store_id;
IF OBJECT_ID(N'dbo.SaleQrPayment', N'U') IS NULL
 CREATE TABLE dbo.SaleQrPayment (
  PaymentId BIGINT IDENTITY PRIMARY KEY,
  OrderId INT NOT NULL,
  PaymentCode NVARCHAR(80) NOT NULL UNIQUE,
  AccountId INT NOT NULL REFERENCES dbo.QrReceivingAccount(AccountId),
  BankCode NVARCHAR(50) NOT NULL,
  AccountNumber NVARCHAR(50) NOT NULL,
  AccountOwner NVARCHAR(150) NOT NULL,
  Amount DECIMAL(18,2) NOT NULL CHECK(Amount > 0),
  AutoConfirmed BIT NOT NULL,
  ReferenceCode NVARCHAR(1000) NULL,
  CreatedAt DATETIME2 NOT NULL DEFAULT SYSDATETIME()
 );
COMMIT;
