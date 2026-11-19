-- Ghi bút toán vốn tiền mặt đầu kỳ cho DBMyShop theo kế hoạch đối soát.
-- Dùng transaction hiện có của OnlineSqlUpdater hoặc tự mở khi chạy trực tiếp.
-- Hai bản vá dữ liệu này chỉ dành cho cài đặt DBMyShop đã đối soát.
SET NOCOUNT ON;

IF DB_NAME() <> N'DBMyShop'
   OR COL_LENGTH(N'dbo.app_installation_identity', N'installation_id') IS NULL
   OR COL_LENGTH(N'dbo.app_installation_identity', N'id') IS NULL
BEGIN
    PRINT N'Bỏ qua bản vá dữ liệu ngoài cơ sở dữ liệu đích.';
    RETURN;
END;

DECLARE @DatabaseFingerprint binary(32);
EXEC sys.sp_executesql N'
    SELECT @Fingerprint = HASHBYTES(''SHA2_256'', CONCAT(
        CONVERT(nvarchar(128), SERVERPROPERTY(''MachineName'')), N''|'',
        CONVERT(nvarchar(128), SERVERPROPERTY(''InstanceName'')), N''|'', DB_NAME(), N''|'',
        CONVERT(nvarchar(36), i.installation_id), N''|'', CONVERT(nvarchar(36), d.service_broker_guid)))
    FROM dbo.app_installation_identity i
    JOIN sys.databases d ON d.database_id = DB_ID()
    WHERE i.id = 1 AND i.installation_id IS NOT NULL;',
    N'@Fingerprint binary(32) OUTPUT', @Fingerprint = @DatabaseFingerprint OUTPUT;

IF @DatabaseFingerprint IS NULL OR @DatabaseFingerprint <> 0x3BD0131CFDC6CC08421A123AC68FD732DF4AC36FB45F24550D01E53C5212461C
BEGIN
    PRINT N'Bỏ qua bản vá dữ liệu vì định danh cơ sở dữ liệu khác đích.';
    RETURN;
END;

DECLARE @OwnTransaction bit = CASE WHEN @@TRANCOUNT = 0 THEN 1 ELSE 0 END;
BEGIN TRY
    IF @OwnTransaction = 1
        BEGIN TRANSACTION;

    -- Chỉ phân giải các bảng nghiệp vụ sau khi đã xác nhận đúng cài đặt.
    EXEC sys.sp_executesql N'
    DECLARE @EntryCode nvarchar(30) = N''PT-DK-000001'';
    DECLARE @Reference nvarchar(100) = N''DK-TIENMAT-2026'';
    DECLARE @EntryDate datetime = ''2026-11-01T08:00:00'';
    DECLARE @Amount decimal(18, 0) = 600000000;
    DECLARE @CategoryName nvarchar(100) = N''Thu tiền đầu kỳ / Góp vốn'';
    DECLARE @CategoryId int;
    DECLARE @Inserted int = 0;

    IF EXISTS
    (
        SELECT 1 FROM dbo.cashbook_entries WITH (UPDLOCK, HOLDLOCK)
        WHERE reference_code = @Reference
    )
    BEGIN
        IF (SELECT COUNT(*) FROM dbo.cashbook_entries WHERE reference_code = @Reference) <> 1
           OR NOT EXISTS
           (
               SELECT 1 FROM dbo.cashbook_entries e
               JOIN dbo.cashbook_categories c ON c.category_id = e.category_id
               WHERE e.reference_code = @Reference AND e.entry_code = @EntryCode
                 AND e.entry_date = @EntryDate AND e.entry_type = N''IN'' AND e.amount = @Amount
                 AND e.payment_method = N''Tiền mặt'' AND e.is_deleted = 0
                 AND c.affects_profit = 0
           )
            THROW 51174, N''Mã tham chiếu đã có nhưng bút toán không khớp kế hoạch. Hãy đối chiếu sổ quỹ.'', 1;
        PRINT N''Bút toán vốn đầu kỳ đã được ghi nhận.'';
        RETURN;
    END
    ELSE
    BEGIN
        IF OBJECT_ID(N''dbo.pos_ext_period'', N''U'') IS NOT NULL
           AND EXISTS (SELECT 1 FROM dbo.pos_ext_period WITH (HOLDLOCK)
                       WHERE id = 1 AND closed_through >= CONVERT(date, @EntryDate))
            THROW 51175, N''Ngày bút toán thuộc kỳ đã chốt. Hủy thao tác.'', 1;

        IF EXISTS (SELECT 1 FROM dbo.cashbook_entries WITH (UPDLOCK, HOLDLOCK)
                   WHERE entry_code = @EntryCode)
            THROW 51176, N''Mã phiếu thu đầu kỳ đã được dùng cho bút toán khác.'', 1;

        -- Giữ khoản vốn ngoài doanh thu và lợi nhuận. Danh mục NULL được
        -- báo cáo hiện tại mặc định tính vào lợi nhuận.
        SELECT TOP (1) @CategoryId = category_id
        FROM dbo.cashbook_categories WITH (UPDLOCK, HOLDLOCK)
        WHERE category_type = N''IN'' AND category_name = @CategoryName
          AND affects_profit = 0 AND is_active = 1
        ORDER BY category_id;

        IF @CategoryId IS NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM dbo.cashbook_categories
                       WHERE category_type = N''IN'' AND category_name = @CategoryName)
                THROW 51177, N''Danh mục vốn đầu kỳ đã tồn tại nhưng không có cấu hình phù hợp.'', 1;

            INSERT dbo.cashbook_categories
                (category_type, category_name, is_system, is_active, affects_profit, sort_order, created_at)
            VALUES (N''IN'', @CategoryName, 0, 1, 0, 100, GETDATE());
            SET @CategoryId = CONVERT(int, SCOPE_IDENTITY());
        END

        INSERT dbo.cashbook_entries
            (entry_code, entry_date, entry_type, category_id, category_name, amount, payment_method,
             description, reference_code, created_by, created_at, is_deleted)
        VALUES (@EntryCode, @EntryDate, N''IN'', @CategoryId, @CategoryName, @Amount, N''Tiền mặt'',
                N''Nạp số dư tiền mặt đầu kỳ hoạt động cửa hàng'', @Reference, N''1'', GETDATE(), 0);
        SET @Inserted = @@ROWCOUNT;
    END


    SELECT @Inserted AS SoButToanDaThem, e.entry_code, e.entry_date, e.amount, c.affects_profit
    FROM dbo.cashbook_entries e JOIN dbo.cashbook_categories c ON c.category_id = e.category_id
    WHERE e.reference_code = @Reference AND e.is_deleted = 0;

    SELECT ISNULL(SUM(CASE WHEN entry_type = N''IN'' THEN amount
                           WHEN entry_type = N''OUT'' THEN -amount ELSE 0 END), 0) AS SoDuTienMat
    FROM dbo.cashbook_entries
    WHERE is_deleted = 0 AND payment_method = N''Tiền mặt'';
    ';

    IF @OwnTransaction = 1
        COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @OwnTransaction = 1 AND XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
