/* Hotfix 2026-07-17
   - Prevent duplicate supplier-return saves from reducing stock twice.
   - Remove empty first stocktake rows caused by check_id = 0.
   - Update Database_ResetData so future resets do not reseed inventory_checks to 0.

   Safe to run on an existing customer database. This script does NOT reset business data.
*/

IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NOT NULL
BEGIN
    ;WITH DuplicateReturns AS
    (
        SELECT
            return_id,
            return_code,
            ROW_NUMBER() OVER (PARTITION BY return_code ORDER BY return_id) AS row_num
        FROM dbo.purchase_returns
    )
    UPDATE pr
    SET return_code = LEFT(pr.return_code, 30 - LEN(CAST(pr.return_id AS VARCHAR(11))) - 1) + '-' + CAST(pr.return_id AS VARCHAR(11))
    FROM dbo.purchase_returns pr
    INNER JOIN DuplicateReturns d ON d.return_id = pr.return_id
    WHERE d.row_num > 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.indexes
        WHERE object_id = OBJECT_ID(N'dbo.purchase_returns')
          AND name = N'UX_purchase_returns_return_code'
    )
    BEGIN
        CREATE UNIQUE NONCLUSTERED INDEX UX_purchase_returns_return_code
        ON dbo.purchase_returns(return_code);
    END
END
GO

IF OBJECT_ID(N'dbo.PurchaseReturns_Insert', N'P') IS NULL
    EXEC(N'CREATE PROCEDURE dbo.PurchaseReturns_Insert AS BEGIN SET NOCOUNT ON; END');
GO

ALTER PROCEDURE [dbo].[PurchaseReturns_Insert]
    @ReturnCode VARCHAR(30),
    @ImportId INT,
    @SupplierId INT,
    @EmployeeId INT,
    @TotalAmount DECIMAL(18,0),
    @Note NVARCHAR(MAX),
    @DetailsXml NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ExistingReturnId INT;

    SELECT TOP 1 @ExistingReturnId = return_id
    FROM dbo.purchase_returns
    WHERE return_code = @ReturnCode;

    IF @ExistingReturnId IS NOT NULL
    BEGIN
        SELECT @ExistingReturnId AS ReturnId;
        RETURN;
    END

    DECLARE @xml XML;
    SET @xml = TRY_CAST(@DetailsXml AS XML);

    IF @xml IS NULL
    BEGIN
        RAISERROR(N'Du lieu chi tiet tra hang khong hop le.', 16, 1);
        RETURN;
    END

    DECLARE @Detail TABLE
    (
        ImportDetailId INT NOT NULL,
        ProductId INT NOT NULL,
        Quantity INT NOT NULL,
        ImportPrice DECIMAL(18,0) NOT NULL,
        Reason NVARCHAR(255) NULL
    );

    INSERT INTO @Detail(ImportDetailId, ProductId, Quantity, ImportPrice, Reason)
    SELECT
        X.Item.value('@ImportDetailId', 'INT'),
        X.Item.value('@ProductId', 'INT'),
        X.Item.value('@Quantity', 'INT'),
        X.Item.value('@ImportPrice', 'DECIMAL(18,0)'),
        X.Item.value('@Reason', 'NVARCHAR(255)')
    FROM @xml.nodes('/Details/Item') AS X(Item);

    IF NOT EXISTS (SELECT 1 FROM @Detail)
    BEGIN
        RAISERROR(N'Chua co san pham tra nha cung cap.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @Detail WHERE Quantity <= 0)
    BEGIN
        RAISERROR(N'So luong tra phai lon hon 0.', 16, 1);
        RETURN;
    END

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.imports i
        WHERE i.import_id = @ImportId
          AND i.supplier_id = @SupplierId
          AND ISNULL(i.status, N'') IN (N'Completed', N'Paid')
    )
    BEGIN
        RAISERROR(N'Phieu nhap khong hop le hoac chua nhap kho.', 16, 1);
        RETURN;
    END

    IF EXISTS
    (
        SELECT 1
        FROM @Detail d
        LEFT JOIN dbo.import_details id ON id.import_detail_id = d.ImportDetailId
        WHERE id.import_detail_id IS NULL
           OR id.import_id <> @ImportId
           OR id.product_id <> d.ProductId
    )
    BEGIN
        RAISERROR(N'San pham tra khong thuoc phieu nhap da chon.', 16, 1);
        RETURN;
    END

    IF EXISTS
    (
        SELECT 1
        FROM @Detail d
        INNER JOIN dbo.import_details id ON id.import_detail_id = d.ImportDetailId
        OUTER APPLY
        (
            SELECT ISNULL(SUM(prd.quantity), 0) AS ReturnedQty
            FROM dbo.purchase_return_details prd
            INNER JOIN dbo.purchase_returns pr ON pr.return_id = prd.return_id
            WHERE prd.import_detail_id = id.import_detail_id
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Da huy', N'Huy', N'Đã hủy', N'Hủy')
        ) r
        WHERE d.Quantity > (ISNULL(id.quantity, 0) - ISNULL(r.ReturnedQty, 0))
    )
    BEGIN
        RAISERROR(N'So luong tra vuot qua so luong con co the tra cua phieu nhap.', 16, 1);
        RETURN;
    END

    IF EXISTS
    (
        SELECT 1
        FROM @Detail d
        INNER JOIN dbo.products p ON p.product_id = d.ProductId
        WHERE ISNULL(p.stock, 0) < d.Quantity
    )
    BEGIN
        RAISERROR(N'Ton kho hien tai khong du de tra nha cung cap. Vui long kiem tra lai kho.', 16, 1);
        RETURN;
    END

    DECLARE @CalcTotal DECIMAL(18,0);
    SELECT @CalcTotal = ISNULL(SUM(Quantity * ImportPrice), 0) FROM @Detail;

    BEGIN TRY
        BEGIN TRANSACTION;

        INSERT INTO dbo.purchase_returns
        (
            return_code,
            import_id,
            supplier_id,
            employee_id,
            return_date,
            total_amount,
            note,
            status
        )
        VALUES
        (
            @ReturnCode,
            @ImportId,
            @SupplierId,
            @EmployeeId,
            GETDATE(),
            @CalcTotal,
            @Note,
            N'Completed'
        );

        DECLARE @ReturnId INT;
        SET @ReturnId = SCOPE_IDENTITY();

        INSERT INTO dbo.purchase_return_details
        (
            return_id,
            import_detail_id,
            product_id,
            quantity,
            import_price,
            total,
            reason
        )
        SELECT
            @ReturnId,
            ImportDetailId,
            ProductId,
            Quantity,
            ImportPrice,
            Quantity * ImportPrice,
            Reason
        FROM @Detail;

        UPDATE p
        SET p.stock = ISNULL(p.stock, 0) - d.Quantity
        FROM dbo.products p
        INNER JOIN @Detail d ON d.ProductId = p.product_id;

        COMMIT TRANSACTION;

        SELECT @ReturnId AS ReturnId;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        IF ERROR_NUMBER() IN (2601, 2627)
        BEGIN
            SELECT TOP 1 @ExistingReturnId = return_id
            FROM dbo.purchase_returns
            WHERE return_code = @ReturnCode;

            IF @ExistingReturnId IS NOT NULL
            BEGIN
                SELECT @ExistingReturnId AS ReturnId;
                RETURN;
            END
        END

        DECLARE @Err NVARCHAR(4000);
        SET @Err = ERROR_MESSAGE();
        RAISERROR(@Err, 16, 1);
    END CATCH
END
GO

IF OBJECT_ID(N'dbo.inventory_checks', N'U') IS NOT NULL
   AND OBJECT_ID(N'dbo.inventory_check_details', N'U') IS NOT NULL
BEGIN
    DELETE ic
    FROM dbo.inventory_checks ic
    WHERE ic.check_id = 0
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.inventory_check_details d
          WHERE d.check_id = ic.check_id
      );
END
GO

IF OBJECT_ID(N'dbo.inventory_checks', N'U') IS NOT NULL
   AND NOT EXISTS (SELECT 1 FROM dbo.inventory_checks WHERE check_id >= 1)
BEGIN
    DBCC CHECKIDENT ('dbo.inventory_checks', RESEED, 1) WITH NO_INFOMSGS;
END
GO

DECLARE @ResetProcSql NVARCHAR(MAX);
SET @ResetProcSql = OBJECT_DEFINITION(OBJECT_ID(N'dbo.Database_ResetData'));

IF @ResetProcSql IS NOT NULL
BEGIN
    SET @ResetProcSql = REPLACE(@ResetProcSql, N'CREATE PROCEDURE [dbo].[Database_ResetData]', N'ALTER PROCEDURE [dbo].[Database_ResetData]');
    SET @ResetProcSql = REPLACE(@ResetProcSql, N'CREATE PROCEDURE dbo.Database_ResetData', N'ALTER PROCEDURE dbo.Database_ResetData');
    SET @ResetProcSql = REPLACE(
        @ResetProcSql,
        N'DBCC CHECKIDENT (''dbo.inventory_checks'', RESEED, 0) WITH NO_INFOMSGS;',
        N'DBCC CHECKIDENT (''dbo.inventory_checks'', RESEED, 1) WITH NO_INFOMSGS;'
    );

    EXEC sp_executesql @ResetProcSql;
END
GO
