/* Feature 2026-08-09
   Add isolated cashbook module for manual income/expense tracking.
   Safe to run on an existing database. This script does NOT reset business data.
*/

IF OBJECT_ID(N'dbo.cashbook_categories', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.cashbook_categories
    (
        category_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_cashbook_categories PRIMARY KEY,
        category_type NVARCHAR(10) NOT NULL,
        category_name NVARCHAR(100) NOT NULL,
        is_system BIT NOT NULL CONSTRAINT DF_cashbook_categories_is_system DEFAULT (0),
        is_active BIT NOT NULL CONSTRAINT DF_cashbook_categories_is_active DEFAULT (1),
        affects_profit BIT NOT NULL CONSTRAINT DF_cashbook_categories_affects_profit DEFAULT (1),
        sort_order INT NOT NULL CONSTRAINT DF_cashbook_categories_sort_order DEFAULT (0),
        created_at DATETIME NOT NULL CONSTRAINT DF_cashbook_categories_created_at DEFAULT (GETDATE())
    );
END
GO

IF OBJECT_ID(N'dbo.cashbook_categories', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.cashbook_categories', N'affects_profit') IS NULL
BEGIN
    ALTER TABLE dbo.cashbook_categories
    ADD affects_profit BIT NOT NULL
        CONSTRAINT DF_cashbook_categories_affects_profit DEFAULT (1);
END
GO

IF OBJECT_ID(N'dbo.cashbook_entries', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.cashbook_entries
    (
        entry_id INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_cashbook_entries PRIMARY KEY,
        entry_code NVARCHAR(30) NULL,
        entry_date DATETIME NOT NULL CONSTRAINT DF_cashbook_entries_entry_date DEFAULT (GETDATE()),
        entry_type NVARCHAR(10) NOT NULL,
        category_id INT NULL,
        category_name NVARCHAR(100) NOT NULL,
        amount DECIMAL(18,0) NOT NULL,
        payment_method NVARCHAR(50) NOT NULL CONSTRAINT DF_cashbook_entries_payment_method DEFAULT (N'Tiền mặt'),
        description NVARCHAR(500) NULL,
        reference_code NVARCHAR(100) NULL,
        created_by NVARCHAR(100) NULL,
        created_at DATETIME NOT NULL CONSTRAINT DF_cashbook_entries_created_at DEFAULT (GETDATE()),
        updated_at DATETIME NULL,
        is_deleted BIT NOT NULL CONSTRAINT DF_cashbook_entries_is_deleted DEFAULT (0)
    );
END
GO

IF OBJECT_ID(N'dbo.CK_cashbook_categories_type', N'C') IS NULL
BEGIN
    ALTER TABLE dbo.cashbook_categories
    ADD CONSTRAINT CK_cashbook_categories_type CHECK (category_type IN (N'IN', N'OUT'));
END
GO

IF OBJECT_ID(N'dbo.CK_cashbook_entries_type', N'C') IS NULL
BEGIN
    ALTER TABLE dbo.cashbook_entries
    ADD CONSTRAINT CK_cashbook_entries_type CHECK (entry_type IN (N'IN', N'OUT'));
END
GO

IF OBJECT_ID(N'dbo.CK_cashbook_entries_amount', N'C') IS NULL
BEGIN
    ALTER TABLE dbo.cashbook_entries
    ADD CONSTRAINT CK_cashbook_entries_amount CHECK (amount > 0);
END
GO

IF OBJECT_ID(N'dbo.FK_cashbook_entries_category', N'F') IS NULL
BEGIN
    ALTER TABLE dbo.cashbook_entries
    ADD CONSTRAINT FK_cashbook_entries_category
        FOREIGN KEY (category_id) REFERENCES dbo.cashbook_categories(category_id);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_cashbook_entries_code' AND object_id = OBJECT_ID(N'dbo.cashbook_entries'))
    CREATE UNIQUE INDEX UX_cashbook_entries_code ON dbo.cashbook_entries(entry_code) WHERE entry_code IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cashbook_entries_date' AND object_id = OBJECT_ID(N'dbo.cashbook_entries'))
    CREATE INDEX IX_cashbook_entries_date ON dbo.cashbook_entries(entry_date, entry_id DESC) INCLUDE (entry_type, amount, is_deleted);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cashbook_entries_type' AND object_id = OBJECT_ID(N'dbo.cashbook_entries'))
    CREATE INDEX IX_cashbook_entries_type ON dbo.cashbook_entries(entry_type, is_deleted, entry_date);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_cashbook_categories_type' AND object_id = OBJECT_ID(N'dbo.cashbook_categories'))
    CREATE INDEX IX_cashbook_categories_type ON dbo.cashbook_categories(category_type, is_active, sort_order, category_name);
GO

IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_categories WHERE category_type = N'IN' AND category_name = N'Thu khác')
    INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, sort_order) VALUES (N'IN', N'Thu khác', 1, 10);
IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_categories WHERE category_type = N'IN' AND category_name = N'Góp vốn')
    INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, sort_order) VALUES (N'IN', N'Góp vốn', 1, 20);
IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_categories WHERE category_type = N'IN' AND category_name = N'Thu nợ khách hàng')
    INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, sort_order) VALUES (N'IN', N'Thu nợ khách hàng', 1, 30);
IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_categories WHERE category_type = N'IN' AND category_name = N'Hoàn tiền nhà cung cấp')
    INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, sort_order) VALUES (N'IN', N'Hoàn tiền nhà cung cấp', 1, 40);
IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_categories WHERE category_type = N'OUT' AND category_name = N'Chi khác')
    INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, sort_order) VALUES (N'OUT', N'Chi khác', 1, 10);
IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_categories WHERE category_type = N'OUT' AND category_name = N'Lương nhân viên')
    INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, sort_order) VALUES (N'OUT', N'Lương nhân viên', 1, 20);
IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_categories WHERE category_type = N'OUT' AND category_name = N'Tiền điện')
    INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, sort_order) VALUES (N'OUT', N'Tiền điện', 1, 30);
IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_categories WHERE category_type = N'OUT' AND category_name = N'Tiền nước')
    INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, sort_order) VALUES (N'OUT', N'Tiền nước', 1, 40);
IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_categories WHERE category_type = N'OUT' AND category_name = N'Thuê nhà')
    INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, sort_order) VALUES (N'OUT', N'Thuê nhà', 1, 50);
IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_categories WHERE category_type = N'OUT' AND category_name = N'Internet')
    INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, sort_order) VALUES (N'OUT', N'Internet', 1, 60);
IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_categories WHERE category_type = N'OUT' AND category_name = N'Vận chuyển')
    INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, sort_order) VALUES (N'OUT', N'Vận chuyển', 1, 70);
IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_categories WHERE category_type = N'OUT' AND category_name = N'Văn phòng phẩm')
    INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, sort_order) VALUES (N'OUT', N'Văn phòng phẩm', 1, 80);
IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_categories WHERE category_type = N'OUT' AND category_name = N'Chi trả nhà cung cấp')
    INSERT INTO dbo.cashbook_categories(category_type, category_name, is_system, sort_order) VALUES (N'OUT', N'Chi trả nhà cung cấp', 1, 90);
GO

IF OBJECT_ID(N'dbo.cashbook_categories', N'U') IS NOT NULL
   AND COL_LENGTH(N'dbo.cashbook_categories', N'affects_profit') IS NOT NULL
BEGIN
    UPDATE dbo.cashbook_categories
    SET affects_profit = 0
    WHERE category_name IN (N'Góp vốn', N'Thu nợ khách hàng', N'Hoàn tiền nhà cung cấp', N'Chi trả nhà cung cấp');
END
GO

IF OBJECT_ID(N'dbo.Cashbook_GetCategories', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Cashbook_GetCategories @Type NVARCHAR(10) = NULL AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Cashbook_GetCategories
    @Type NVARCHAR(10) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Type = NULLIF(UPPER(LTRIM(RTRIM(ISNULL(@Type, N'')))), N'');

    SELECT
        category_id AS CategoryId,
        category_type AS CategoryType,
        category_name AS CategoryName,
        is_system AS IsSystem,
        is_active AS IsActive,
        sort_order AS SortOrder
    FROM dbo.cashbook_categories
    WHERE is_active = 1
      AND (@Type IS NULL OR category_type = @Type)
    ORDER BY category_type, sort_order, category_name;
END
GO

IF OBJECT_ID(N'dbo.Cashbook_Search', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Cashbook_Search @FromDate DATETIME, @ToDate DATETIME, @Type NVARCHAR(10) = NULL, @Keyword NVARCHAR(200) = NULL AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Cashbook_Search
    @FromDate DATETIME,
    @ToDate DATETIME,
    @Type NVARCHAR(10) = NULL,
    @Keyword NVARCHAR(200) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @Type = NULLIF(UPPER(LTRIM(RTRIM(ISNULL(@Type, N'')))), N'');
    SET @Keyword = NULLIF(LTRIM(RTRIM(ISNULL(@Keyword, N''))), N'');

    SELECT
        entry_id AS EntryId,
        entry_code AS EntryCode,
        entry_date AS EntryDate,
        entry_type AS EntryType,
        category_id AS CategoryId,
        category_name AS CategoryName,
        amount AS Amount,
        payment_method AS PaymentMethod,
        description AS Description,
        reference_code AS ReferenceCode,
        created_by AS CreatedBy,
        created_at AS CreatedAt,
        updated_at AS UpdatedAt
    FROM dbo.cashbook_entries
    WHERE is_deleted = 0
      AND entry_date >= @FromDate
      AND entry_date < DATEADD(DAY, 1, @ToDate)
      AND (@Type IS NULL OR entry_type = @Type)
      AND
      (
          @Keyword IS NULL
          OR entry_code LIKE N'%' + @Keyword + N'%'
          OR category_name LIKE N'%' + @Keyword + N'%'
          OR payment_method LIKE N'%' + @Keyword + N'%'
          OR reference_code LIKE N'%' + @Keyword + N'%'
          OR description LIKE N'%' + @Keyword + N'%'
          OR created_by LIKE N'%' + @Keyword + N'%'
      )
    ORDER BY entry_date DESC, entry_id DESC;
END
GO

IF OBJECT_ID(N'dbo.Cashbook_GetSummary', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Cashbook_GetSummary @FromDate DATETIME, @ToDate DATETIME AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Cashbook_GetSummary
    @FromDate DATETIME,
    @ToDate DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ISNULL(SUM(CASE WHEN entry_type = N'IN' THEN amount ELSE 0 END), 0) AS TotalIn,
        ISNULL(SUM(CASE WHEN entry_type = N'OUT' THEN amount ELSE 0 END), 0) AS TotalOut,
        ISNULL(SUM(CASE WHEN entry_type = N'IN' THEN amount ELSE -amount END), 0) AS Balance,
        COUNT(1) AS EntryCount
    FROM dbo.cashbook_entries
    WHERE is_deleted = 0
      AND entry_date >= @FromDate
      AND entry_date < DATEADD(DAY, 1, @ToDate);
END
GO

IF OBJECT_ID(N'dbo.Cashbook_Insert', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Cashbook_Insert @EntryDate DATETIME, @EntryType NVARCHAR(10), @Amount DECIMAL(18,0), @CategoryId INT = NULL, @CategoryName NVARCHAR(100) = NULL, @PaymentMethod NVARCHAR(50) = NULL, @Description NVARCHAR(500) = NULL, @ReferenceCode NVARCHAR(100) = NULL, @CreatedBy NVARCHAR(100) = NULL AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Cashbook_Insert
    @EntryDate DATETIME,
    @EntryType NVARCHAR(10),
    @Amount DECIMAL(18,0),
    @CategoryId INT = NULL,
    @CategoryName NVARCHAR(100) = NULL,
    @PaymentMethod NVARCHAR(50) = NULL,
    @Description NVARCHAR(500) = NULL,
    @ReferenceCode NVARCHAR(100) = NULL,
    @CreatedBy NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ResolvedCategoryName NVARCHAR(100);
    DECLARE @EntryId INT;
    DECLARE @EntryCode NVARCHAR(30);

    SET @EntryType = UPPER(LTRIM(RTRIM(ISNULL(@EntryType, N''))));
    SET @PaymentMethod = ISNULL(NULLIF(LTRIM(RTRIM(@PaymentMethod)), N''), N'Tiền mặt');
    SET @CategoryName = NULLIF(LTRIM(RTRIM(ISNULL(@CategoryName, N''))), N'');
    SET @Description = NULLIF(LTRIM(RTRIM(ISNULL(@Description, N''))), N'');
    SET @ReferenceCode = NULLIF(LTRIM(RTRIM(ISNULL(@ReferenceCode, N''))), N'');
    SET @CreatedBy = NULLIF(LTRIM(RTRIM(ISNULL(@CreatedBy, N''))), N'');

    IF @EntryType NOT IN (N'IN', N'OUT')
    BEGIN
        RAISERROR(N'Loại phiếu sổ quỹ không hợp lệ.', 16, 1);
        RETURN;
    END

    IF ISNULL(@Amount, 0) <= 0
    BEGIN
        RAISERROR(N'Số tiền phải lớn hơn 0.', 16, 1);
        RETURN;
    END

    SELECT @ResolvedCategoryName = category_name
    FROM dbo.cashbook_categories
    WHERE category_id = @CategoryId
      AND category_type = @EntryType
      AND is_active = 1;

    IF @ResolvedCategoryName IS NULL
    BEGIN
        SET @CategoryId = NULL;
        SET @ResolvedCategoryName = ISNULL(@CategoryName, CASE WHEN @EntryType = N'IN' THEN N'Thu khác' ELSE N'Chi khác' END);
    END

    INSERT INTO dbo.cashbook_entries
    (
        entry_date,
        entry_type,
        category_id,
        category_name,
        amount,
        payment_method,
        description,
        reference_code,
        created_by
    )
    VALUES
    (
        @EntryDate,
        @EntryType,
        @CategoryId,
        @ResolvedCategoryName,
        @Amount,
        @PaymentMethod,
        @Description,
        @ReferenceCode,
        @CreatedBy
    );

    SET @EntryId = CONVERT(INT, SCOPE_IDENTITY());
    SET @EntryCode = N'SQ' + CONVERT(CHAR(6), @EntryDate, 12) + RIGHT(N'000000' + CAST(@EntryId AS NVARCHAR(20)), 6);

    UPDATE dbo.cashbook_entries
    SET entry_code = @EntryCode
    WHERE entry_id = @EntryId;

    SELECT
        entry_id AS EntryId,
        entry_code AS EntryCode,
        entry_date AS EntryDate,
        entry_type AS EntryType,
        category_id AS CategoryId,
        category_name AS CategoryName,
        amount AS Amount,
        payment_method AS PaymentMethod,
        description AS Description,
        reference_code AS ReferenceCode,
        created_by AS CreatedBy,
        created_at AS CreatedAt,
        updated_at AS UpdatedAt
    FROM dbo.cashbook_entries
    WHERE entry_id = @EntryId;
END
GO

IF OBJECT_ID(N'dbo.Cashbook_Update', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Cashbook_Update @EntryId INT, @EntryDate DATETIME, @EntryType NVARCHAR(10), @Amount DECIMAL(18,0), @CategoryId INT = NULL, @CategoryName NVARCHAR(100) = NULL, @PaymentMethod NVARCHAR(50) = NULL, @Description NVARCHAR(500) = NULL, @ReferenceCode NVARCHAR(100) = NULL AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Cashbook_Update
    @EntryId INT,
    @EntryDate DATETIME,
    @EntryType NVARCHAR(10),
    @Amount DECIMAL(18,0),
    @CategoryId INT = NULL,
    @CategoryName NVARCHAR(100) = NULL,
    @PaymentMethod NVARCHAR(50) = NULL,
    @Description NVARCHAR(500) = NULL,
    @ReferenceCode NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ResolvedCategoryName NVARCHAR(100);

    SET @EntryType = UPPER(LTRIM(RTRIM(ISNULL(@EntryType, N''))));
    SET @PaymentMethod = ISNULL(NULLIF(LTRIM(RTRIM(@PaymentMethod)), N''), N'Tiền mặt');
    SET @CategoryName = NULLIF(LTRIM(RTRIM(ISNULL(@CategoryName, N''))), N'');
    SET @Description = NULLIF(LTRIM(RTRIM(ISNULL(@Description, N''))), N'');
    SET @ReferenceCode = NULLIF(LTRIM(RTRIM(ISNULL(@ReferenceCode, N''))), N'');

    IF @EntryType NOT IN (N'IN', N'OUT')
    BEGIN
        RAISERROR(N'Loại phiếu sổ quỹ không hợp lệ.', 16, 1);
        RETURN;
    END

    IF ISNULL(@Amount, 0) <= 0
    BEGIN
        RAISERROR(N'Số tiền phải lớn hơn 0.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS (SELECT 1 FROM dbo.cashbook_entries WHERE entry_id = @EntryId AND is_deleted = 0)
    BEGIN
        RAISERROR(N'Không tìm thấy phiếu sổ quỹ cần sửa.', 16, 1);
        RETURN;
    END

    SELECT @ResolvedCategoryName = category_name
    FROM dbo.cashbook_categories
    WHERE category_id = @CategoryId
      AND category_type = @EntryType
      AND is_active = 1;

    IF @ResolvedCategoryName IS NULL
    BEGIN
        SET @CategoryId = NULL;
        SET @ResolvedCategoryName = ISNULL(@CategoryName, CASE WHEN @EntryType = N'IN' THEN N'Thu khác' ELSE N'Chi khác' END);
    END

    UPDATE dbo.cashbook_entries
    SET
        entry_date = @EntryDate,
        entry_type = @EntryType,
        category_id = @CategoryId,
        category_name = @ResolvedCategoryName,
        amount = @Amount,
        payment_method = @PaymentMethod,
        description = @Description,
        reference_code = @ReferenceCode,
        updated_at = GETDATE()
    WHERE entry_id = @EntryId
      AND is_deleted = 0;

    SELECT
        entry_id AS EntryId,
        entry_code AS EntryCode,
        entry_date AS EntryDate,
        entry_type AS EntryType,
        category_id AS CategoryId,
        category_name AS CategoryName,
        amount AS Amount,
        payment_method AS PaymentMethod,
        description AS Description,
        reference_code AS ReferenceCode,
        created_by AS CreatedBy,
        created_at AS CreatedAt,
        updated_at AS UpdatedAt
    FROM dbo.cashbook_entries
    WHERE entry_id = @EntryId;
END
GO

IF OBJECT_ID(N'dbo.Cashbook_Delete', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Cashbook_Delete @EntryId INT AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Cashbook_Delete
    @EntryId INT
AS
BEGIN
    SET NOCOUNT ON;

    UPDATE dbo.cashbook_entries
    SET is_deleted = 1,
        updated_at = GETDATE()
    WHERE entry_id = @EntryId
      AND is_deleted = 0;

    SELECT @@ROWCOUNT AS AffectedRows;
END
GO
