-- Vá Serial còn thiếu của phiếu PN2611180544000005 trên DBMyShop.
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
    DECLARE @ImportId int = 5;
    DECLARE @Expected TABLE
    (
        product_id int PRIMARY KEY,
        serial_number nvarchar(100) NOT NULL UNIQUE
    );
    INSERT @Expected (product_id, serial_number)
    VALUES (51, N''356181128000060''), (52, N''356182256000069''),
           (53, N''356183128000068''), (54, N''356184256000067''),
           (55, N''356185512000066'');

    -- Các mã có thể đã bán sau khi bản vá được chạy thủ công.
    IF NOT EXISTS
    (
        SELECT 1
        FROM @Expected e
        OUTER APPLY
        (
            SELECT COUNT(*) AS MatchingSerials
            FROM dbo.product_serials s WITH (UPDLOCK, HOLDLOCK)
            WHERE s.import_id = @ImportId AND s.product_id = e.product_id
              AND LTRIM(RTRIM(s.serial_number)) = e.serial_number
        ) s
        WHERE s.MatchingSerials <> 1
    )
    BEGIN
        PRINT N''Phiếu nhập số 5 đã có đủ năm mã Serial của bản vá.'';
        RETURN;
    END;

    IF NOT EXISTS
    (
        SELECT 1 FROM dbo.imports WITH (UPDLOCK, HOLDLOCK)
        WHERE import_id = @ImportId AND import_code = ''PN2611180544000005''
          AND status IN (N''Completed'', N''Paid'')
    )
        THROW 51170, N''Phiếu nhập số 5 không khớp mã phiếu đã chốt trong kế hoạch.'', 1;

    IF EXISTS
    (
        SELECT 1
        FROM @Expected e
        LEFT JOIN dbo.products p WITH (UPDLOCK, HOLDLOCK) ON p.product_id = e.product_id
        OUTER APPLY
        (
            SELECT SUM(COALESCE(NULLIF(d.base_quantity, 0),
                       d.quantity * COALESCE(NULLIF(d.unit_conversion_to_base, 0), 1))) AS BaseQuantity
            FROM dbo.import_details d WITH (HOLDLOCK)
            WHERE d.import_id = @ImportId AND d.product_id = e.product_id
        ) d
        WHERE p.product_id IS NULL OR ISNULL(p.has_serial, 0) <> 1
           OR ISNULL(p.stock, 0) <> 6 OR ISNULL(d.BaseQuantity, 0) <> 1
    )
        THROW 51171, N''Sản phẩm, tồn kho hoặc số lượng trên phiếu không khớp kế hoạch. Hãy đối chiếu trước khi vá.'', 1;

    IF EXISTS
    (
        SELECT 1
        FROM @Expected e
        JOIN dbo.product_serials s WITH (UPDLOCK, HOLDLOCK)
          ON LTRIM(RTRIM(s.serial_number)) = e.serial_number
          OR (s.import_id = @ImportId AND s.product_id = e.product_id)
        WHERE s.import_id <> @ImportId OR s.product_id <> e.product_id
           OR ISNULL(LTRIM(RTRIM(s.serial_number)), N'''') <> e.serial_number
           OR ISNULL(s.status, -1) <> 0 OR s.order_id IS NOT NULL
    )
        THROW 51172, N''Phiếu hoặc mã Serial trùng với dữ liệu khác trong kho. Hủy vá dữ liệu.'', 1;

    INSERT INTO dbo.product_serials (product_id, import_id, serial_number, status, created_at)
    SELECT e.product_id, @ImportId, e.serial_number, 0, GETDATE()
    FROM @Expected e
    WHERE NOT EXISTS
    (
        SELECT 1 FROM dbo.product_serials s WITH (UPDLOCK, HOLDLOCK)
        WHERE s.import_id = @ImportId AND s.product_id = e.product_id
          AND LTRIM(RTRIM(s.serial_number)) = e.serial_number
    );
    DECLARE @Inserted int = @@ROWCOUNT;

    SELECT p.product_id, p.product_code, p.product_name, p.stock AS TonKho_Products,
           COUNT(s.serial_id) AS SoLuong_Serial_TrongKho,
           p.stock - COUNT(s.serial_id) AS ChenhLech
    INTO #Import5SerialCheck
    FROM @Expected e
    JOIN dbo.products p ON p.product_id = e.product_id
    LEFT JOIN dbo.product_serials s WITH (HOLDLOCK)
      ON s.product_id = p.product_id AND s.status = 0
    GROUP BY p.product_id, p.product_code, p.product_name, p.stock;

    IF EXISTS (SELECT 1 FROM #Import5SerialCheck WHERE ChenhLech <> 0)
        THROW 51173, N''Số Serial khả dụng chưa khớp tồn kho. Toàn bộ bản vá đã được hủy.'', 1;

    SELECT @Inserted AS SoSerialDaThem;
    SELECT * FROM #Import5SerialCheck ORDER BY product_id;
    DROP TABLE #Import5SerialCheck;
    ';

    IF @OwnTransaction = 1
        COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF @OwnTransaction = 1 AND XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
