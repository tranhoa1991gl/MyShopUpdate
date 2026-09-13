/*
HoaTran POS - 20260913_guest_invoice_compatibility_v1
Shared by the embedded offline migration and OnlineSqlUpdater.
Only upgrades guest/invoice metadata; does not replace a shop database.
Safe to rerun, including inside the updater's existing transaction.
*/
SET XACT_ABORT ON;
DECLARE @OwnTransaction BIT = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
IF @OwnTransaction = 1 BEGIN TRANSACTION;
BEGIN TRY
    DECLARE @LockResult INT;
    EXEC @LockResult = sys.sp_getapplock
        @Resource = N'HoaTranPOS.GuestInvoiceSchema.v1',
        @LockMode = N'Exclusive', @LockOwner = N'Transaction', @LockTimeout = 30000;
    IF @LockResult < 0
        THROW 51001, N'Không thể khóa nâng cấp cấu hình khách lẻ. Vui lòng thử lại.', 1;

    IF OBJECT_ID(N'dbo.customers', N'U') IS NULL OR OBJECT_ID(N'dbo.StoreInfo', N'U') IS NULL
        THROW 51002, N'Database thiếu bảng customers hoặc StoreInfo. Kiểm tra lại database đang kết nối.', 1;

    DECLARE @InitializeInvoiceName BIT =
        CASE WHEN COL_LENGTH(N'dbo.StoreInfo', N'invoice_guest_customer_name') IS NULL THEN 1 ELSE 0 END;

    IF COL_LENGTH(N'dbo.customers', N'is_guest') IS NULL
        ALTER TABLE dbo.customers ADD is_guest BIT NOT NULL DEFAULT (0) WITH VALUES;
    IF COL_LENGTH(N'dbo.customers', N'customer_code') IS NULL
        ALTER TABLE dbo.customers ADD customer_code NVARCHAR(50) NULL;
    IF COL_LENGTH(N'dbo.customers', N'price_group_level') IS NULL
        ALTER TABLE dbo.customers ADD price_group_level INT NOT NULL DEFAULT (0) WITH VALUES;
    IF COL_LENGTH(N'dbo.customers', N'wallet_balance') IS NULL
        ALTER TABLE dbo.customers ADD wallet_balance DECIMAL(18,2) NOT NULL DEFAULT (0) WITH VALUES;
    IF COL_LENGTH(N'dbo.customers', N'points') IS NULL
        ALTER TABLE dbo.customers ADD points INT NOT NULL DEFAULT (0) WITH VALUES;
    IF @InitializeInvoiceName = 1
        ALTER TABLE dbo.StoreInfo ADD invoice_guest_customer_name NVARCHAR(50) NOT NULL
            DEFAULT (N'Khách lẻ') WITH VALUES;

    -- Compile data updates only AFTER the new columns have been created.
    EXEC sys.sp_executesql N'-- Preserve the shop''s explicit choice; infer it only when adding the setting.
IF @InitializeInvoiceName = 1
BEGIN
    UPDATE dbo.StoreInfo
    SET invoice_guest_customer_name = CASE WHEN EXISTS
    (
        SELECT 1 FROM dbo.customers
        WHERE LTRIM(RTRIM(ISNULL(name, N''''))) = N''Bán cho người tiêu dùng''
          AND LTRIM(RTRIM(ISNULL(phone, N''''))) IN (N'''', N''0'')
    ) THEN N''Bán cho người tiêu dùng'' ELSE N''Khách lẻ'' END;
END;

-- A customer code alone never identifies a walk-in customer.
UPDATE dbo.customers
SET is_guest = 0
WHERE is_guest = 1
  AND
  (
      LTRIM(RTRIM(ISNULL(name, N''''))) NOT IN
          (N''Khách lẻ'', N''Người tiêu dùng'', N''Bán cho người tiêu dùng'', N''Khách vãng lai'')
      OR LTRIM(RTRIM(ISNULL(phone, N''''))) NOT IN (N'''', N''0'')
  );

DECLARE @GuestId INT;
SELECT TOP (1) @GuestId = customer_id
FROM dbo.customers WITH (UPDLOCK, HOLDLOCK)
WHERE LTRIM(RTRIM(ISNULL(name, N''''))) IN
    (N''Khách lẻ'', N''Người tiêu dùng'', N''Bán cho người tiêu dùng'', N''Khách vãng lai'')
  AND LTRIM(RTRIM(ISNULL(phone, N''''))) IN (N'''', N''0'')
ORDER BY is_guest DESC, customer_id;

IF @GuestId IS NULL
BEGIN
    DECLARE @GuestName NVARCHAR(50) =
        (SELECT TOP (1) invoice_guest_customer_name FROM dbo.StoreInfo ORDER BY store_id);
    IF @GuestName IS NULL OR @GuestName NOT IN (N''Khách lẻ'', N''Bán cho người tiêu dùng'')
        SET @GuestName = N''Khách lẻ'';

    INSERT INTO dbo.customers
        (customer_code, name, phone, email, address, is_guest, price_group_level, wallet_balance, points, created_at)
    VALUES (NULL, @GuestName, N'''', N'''', N'''', 1, 0, 0, 0, GETDATE());
    SET @GuestId = CONVERT(INT, SCOPE_IDENTITY());
END
ELSE
    UPDATE dbo.customers SET is_guest = 1 WHERE customer_id = @GuestId;

-- Retain imported codes. If a new guest''s usual code is taken, allocate a suffix.
IF EXISTS (SELECT 1 FROM dbo.customers WHERE customer_id = @GuestId
           AND NULLIF(LTRIM(RTRIM(customer_code)), N'''') IS NULL)
BEGIN
    DECLARE @BaseCode NVARCHAR(40) = N''KH'' + RIGHT(N''000000'' + CONVERT(NVARCHAR(20), @GuestId), 6);
    DECLARE @GuestCode NVARCHAR(50) = @BaseCode;
    DECLARE @Suffix INT = 0;
    WHILE EXISTS (SELECT 1 FROM dbo.customers WITH (UPDLOCK, HOLDLOCK)
                  WHERE customer_code = @GuestCode AND customer_id <> @GuestId)
    BEGIN
        SET @Suffix = @Suffix + 1;
        SET @GuestCode = @BaseCode + N''-'' + CONVERT(NVARCHAR(10), @Suffix);
    END;
    UPDATE dbo.customers SET customer_code = @GuestCode WHERE customer_id = @GuestId;
END;',
        N'@InitializeInvoiceName BIT', @InitializeInvoiceName = @InitializeInvoiceName;

    IF COL_LENGTH(N'dbo.customers', N'is_guest') IS NULL
       OR COL_LENGTH(N'dbo.StoreInfo', N'invoice_guest_customer_name') IS NULL
        THROW 51003, N'Chưa nâng cấp đầy đủ cấu hình khách lẻ. Không thể tiếp tục lưu.', 1;

    IF @OwnTransaction = 1 COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @OwnTransaction = 1 AND XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
