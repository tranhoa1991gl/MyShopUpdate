/* Hotfix 2026-08-10
   Cashbook: allow all-time filtering by passing NULL for date range.
*/

IF OBJECT_ID(N'dbo.Cashbook_Search', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.Cashbook_Search @FromDate DATETIME = NULL, @ToDate DATETIME = NULL, @Type NVARCHAR(10) = NULL, @Keyword NVARCHAR(200) = NULL AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Cashbook_Search
    @FromDate DATETIME = NULL,
    @ToDate DATETIME = NULL,
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
      AND (@FromDate IS NULL OR entry_date >= @FromDate)
      AND (@ToDate IS NULL OR entry_date < DATEADD(DAY, 1, @ToDate))
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
    EXEC(N'CREATE PROCEDURE dbo.Cashbook_GetSummary @FromDate DATETIME = NULL, @ToDate DATETIME = NULL AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE dbo.Cashbook_GetSummary
    @FromDate DATETIME = NULL,
    @ToDate DATETIME = NULL
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
      AND (@FromDate IS NULL OR entry_date >= @FromDate)
      AND (@ToDate IS NULL OR entry_date < DATEADD(DAY, 1, @ToDate));
END
GO
