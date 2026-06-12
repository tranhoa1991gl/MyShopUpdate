/*
    MyShop - GỘP SQL CẬP NHẬT BÁO CÁO + TRẢ HÀNG NCC
    MigrationId đề xuất: 2026-06-12-myshop-report-purchase-return-full
    Thứ tự gộp:
      1. Báo cáo xuất nhập tồn
      2. Trả hàng nhà cung cấp
      3. Lịch sử trả hàng nhà cung cấp
      4. Báo cáo tổng quan lợi nhuận có tính trả NCC

    Lưu ý:
      - File này dùng khi muốn chạy 1 migration duy nhất.
      - Nếu đã chạy từng file lẻ trước đó, không cần chạy file gộp này.
*/


--------------------------------------------------------------------------------
-- PHẦN 1: 2026-06-12-inventory-movement-report
--------------------------------------------------------------------------------

/*
    MyShop - Báo cáo Xuất Nhập Tồn
    MigrationId: 2026-06-12-inventory-movement-report
    Chức năng: tạo stored procedure Report_GetInventoryMovement
*/

IF OBJECT_ID(N'dbo.Report_GetInventoryMovement', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Report_GetInventoryMovement;
GO

CREATE OR ALTER PROCEDURE dbo.Report_GetInventoryMovement
    @FromDate DATETIME,
    @ToDate   DATETIME,
    @Keyword  NVARCHAR(200) = N''
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartDate DATETIME;
    DECLARE @EndDateExclusive DATETIME;

    SET @StartDate = CONVERT(DATE, @FromDate);
    SET @EndDateExclusive = DATEADD(DAY, 1, CONVERT(DATE, @ToDate));
    SET @Keyword = LTRIM(RTRIM(ISNULL(@Keyword, N'')));

    ;WITH Movements AS
    (
        -- Nhập mua từ nhà cung cấp: tăng kho
        SELECT
            id.product_id,
            i.import_date AS movement_date,
            CAST(ISNULL(id.base_quantity, id.quantity) AS DECIMAL(18, 3)) AS qty,
            CAST(ISNULL(id.total, ISNULL(id.import_price, 0) * ISNULL(id.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N'PURCHASE_IN' AS movement_type
        FROM dbo.import_details id
        INNER JOIN dbo.imports i ON i.import_id = id.import_id
        WHERE ISNULL(i.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
          AND i.import_date IS NOT NULL
          AND id.product_id IS NOT NULL

        UNION ALL

        -- Xuất bán: giảm kho
        SELECT
            oi.product_id,
            o.order_date AS movement_date,
            -CAST(ISNULL(oi.base_quantity, oi.quantity) AS DECIMAL(18, 3)) AS qty,
            CAST(ISNULL(oi.unit_price, 0) * ABS(ISNULL(oi.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N'SALES_OUT' AS movement_type
        FROM dbo.order_items oi
        INNER JOIN dbo.orders o ON o.order_id = oi.order_id
        WHERE ISNULL(o.status, N'') IN (N'Paid', N'Completed')
          AND ISNULL(o.order_type, N'') <> N'RETURN'
          AND o.order_date IS NOT NULL
          AND oi.product_id IS NOT NULL
          AND ISNULL(oi.quantity, 0) > 0

        UNION ALL

        -- Khách trả hàng: tăng kho. Trong hệ thống phiếu trả đang lưu quantity âm.
        SELECT
            oi.product_id,
            o.order_date AS movement_date,
            ABS(CAST(ISNULL(oi.base_quantity, oi.quantity) AS DECIMAL(18, 3))) AS qty,
            CAST(ISNULL(oi.unit_price, 0) * ABS(ISNULL(oi.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N'RETURN_IN' AS movement_type
        FROM dbo.order_items oi
        INNER JOIN dbo.orders o ON o.order_id = oi.order_id
        WHERE ISNULL(o.status, N'') IN (N'Paid', N'Completed')
          AND ISNULL(o.order_type, N'') = N'RETURN'
          AND o.order_date IS NOT NULL
          AND oi.product_id IS NOT NULL

        UNION ALL

        -- Kiểm kê/chốt kho: tăng hoặc giảm theo cột difference
        SELECT
            icd.product_id,
            ic.check_date AS movement_date,
            CAST(icd.difference AS DECIMAL(18, 3)) AS qty,
            CAST(0 AS DECIMAL(18, 0)) AS amount,
            N'STOCKTAKE' AS movement_type
        FROM dbo.inventory_check_details icd
        INNER JOIN dbo.inventory_checks ic ON ic.check_id = icd.check_id
        WHERE ic.check_date IS NOT NULL
          AND icd.product_id IS NOT NULL
          AND ISNULL(icd.difference, 0) <> 0
    ),
    PeriodSummary AS
    (
        SELECT
            product_id,
            SUM(CASE WHEN movement_type = N'PURCHASE_IN' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS PurchaseInQty,
            SUM(CASE WHEN movement_type = N'SALES_OUT'   AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN ABS(qty) ELSE 0 END) AS SalesOutQty,
            SUM(CASE WHEN movement_type = N'RETURN_IN'   AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS ReturnInQty,
            SUM(CASE WHEN movement_type = N'STOCKTAKE'   AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS StocktakeAdjustQty,
            SUM(CASE WHEN movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS NetPeriodQty,
            SUM(CASE WHEN movement_type = N'PURCHASE_IN' AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS PurchaseInValue,
            SUM(CASE WHEN movement_type = N'SALES_OUT'   AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS SalesOutValue
        FROM Movements
        GROUP BY product_id
    ),
    AfterPeriodSummary AS
    (
        SELECT
            product_id,
            SUM(qty) AS NetAfterPeriodQty
        FROM Movements
        WHERE movement_date >= @EndDateExclusive
        GROUP BY product_id
    )
    SELECT
        p.product_id AS ProductId,
        p.product_code AS ProductCode,
        ISNULL(p.barcode, N'') AS Barcode,
        p.product_name AS ProductName,
        ISNULL(c.category_name, N'') AS CategoryName,
        ISNULL(u.unit_name, N'') AS UnitName,

        CAST(ISNULL(p.stock, 0) - ISNULL(a.NetAfterPeriodQty, 0) - ISNULL(ps.NetPeriodQty, 0) AS DECIMAL(18, 3)) AS OpeningStock,
        CAST(ISNULL(ps.PurchaseInQty, 0) AS DECIMAL(18, 3)) AS PurchaseInQty,
        CAST(ISNULL(ps.ReturnInQty, 0) AS DECIMAL(18, 3)) AS ReturnInQty,
        CAST(ISNULL(ps.StocktakeAdjustQty, 0) AS DECIMAL(18, 3)) AS StocktakeAdjustQty,
        CAST(ISNULL(ps.SalesOutQty, 0) AS DECIMAL(18, 3)) AS SalesOutQty,
        CAST(ISNULL(p.stock, 0) - ISNULL(a.NetAfterPeriodQty, 0) AS DECIMAL(18, 3)) AS ClosingStock,
        CAST(ISNULL(p.stock, 0) AS DECIMAL(18, 3)) AS CurrentStock,

        CAST(ISNULL(ps.PurchaseInValue, 0) AS DECIMAL(18, 0)) AS PurchaseInValue,
        CAST(ISNULL(ps.SalesOutValue, 0) AS DECIMAL(18, 0)) AS SalesOutValue,
        CAST((ISNULL(p.stock, 0) - ISNULL(a.NetAfterPeriodQty, 0)) * ISNULL(p.import_price, 0) AS DECIMAL(18, 0)) AS ClosingCostValue
    FROM dbo.products p
    LEFT JOIN dbo.categories c ON c.category_id = p.category_id
    LEFT JOIN dbo.Units u ON u.unit_id = p.unit_id
    LEFT JOIN PeriodSummary ps ON ps.product_id = p.product_id
    LEFT JOIN AfterPeriodSummary a ON a.product_id = p.product_id
    WHERE ISNULL(p.is_active, 1) = 1
      AND (
            @Keyword = N''
            OR p.product_code LIKE N'%' + @Keyword + N'%'
            OR ISNULL(p.barcode, N'') LIKE N'%' + @Keyword + N'%'
            OR p.product_name LIKE N'%' + @Keyword + N'%'
          )
    ORDER BY p.product_code, p.product_name;
END
GO

--------------------------------------------------------------------------------
-- PHẦN 2: 2026-06-12-purchase-return-supplier
--------------------------------------------------------------------------------

-- =========================================================
-- MyShop - Trả hàng nhà cung cấp + cập nhật báo cáo Xuất Nhập Tồn
-- MigrationId: 2026-06-12-purchase-return-supplier
-- =========================================================

IF OBJECT_ID(N'dbo.purchase_return_details', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.purchase_return_details
    (
        return_detail_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        return_id INT NOT NULL,
        import_detail_id INT NOT NULL,
        product_id INT NOT NULL,
        quantity INT NOT NULL,
        import_price DECIMAL(18,0) NOT NULL,
        total DECIMAL(18,0) NOT NULL,
        reason NVARCHAR(255) NULL
    );
END
GO

IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.purchase_returns
    (
        return_id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        return_code VARCHAR(30) NOT NULL,
        import_id INT NOT NULL,
        supplier_id INT NOT NULL,
        employee_id INT NULL,
        return_date DATETIME NOT NULL CONSTRAINT DF_purchase_returns_return_date DEFAULT(GETDATE()),
        total_amount DECIMAL(18,0) NOT NULL CONSTRAINT DF_purchase_returns_total_amount DEFAULT(0),
        note NVARCHAR(MAX) NULL,
        status NVARCHAR(50) NOT NULL CONSTRAINT DF_purchase_returns_status DEFAULT(N'Completed')
    );

    CREATE UNIQUE INDEX UX_purchase_returns_return_code ON dbo.purchase_returns(return_code);
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_purchase_return_details_return_id' AND object_id = OBJECT_ID(N'dbo.purchase_return_details'))
    CREATE INDEX IX_purchase_return_details_return_id ON dbo.purchase_return_details(return_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_purchase_return_details_import_detail_id' AND object_id = OBJECT_ID(N'dbo.purchase_return_details'))
    CREATE INDEX IX_purchase_return_details_import_detail_id ON dbo.purchase_return_details(import_detail_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_purchase_returns_import_id' AND object_id = OBJECT_ID(N'dbo.purchase_returns'))
    CREATE INDEX IX_purchase_returns_import_id ON dbo.purchase_returns(import_id);
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_purchase_returns_supplier_id' AND object_id = OBJECT_ID(N'dbo.purchase_returns'))
    CREATE INDEX IX_purchase_returns_supplier_id ON dbo.purchase_returns(supplier_id);
GO

IF OBJECT_ID(N'dbo.PurchaseReturns_GetImportsForReturn', N'P') IS NOT NULL
    DROP PROCEDURE dbo.PurchaseReturns_GetImportsForReturn;
GO
CREATE PROCEDURE dbo.PurchaseReturns_GetImportsForReturn
    @FromDate DATETIME,
    @ToDate DATETIME,
    @Keyword NVARCHAR(200) = N''
AS
BEGIN
    SET NOCOUNT ON;

    SET @Keyword = LTRIM(RTRIM(ISNULL(@Keyword, N'')));

    SELECT
        i.import_id AS ImportId,
        i.import_code AS ImportCode,
        i.supplier_id AS SupplierId,
        ISNULL(s.supplier_name, N'') AS SupplierName,
        i.import_date AS ImportDate,
        i.final_amount AS FinalAmount,
        i.status AS Status,
        CASE 
            WHEN i.status = N'Paid' THEN N'Tất toán'
            WHEN i.status = N'Completed' THEN N'Còn nợ'
            ELSE i.status
        END AS StatusText,
        ISNULL((
            SELECT SUM(pr.total_amount)
            FROM dbo.purchase_returns pr
            WHERE pr.import_id = i.import_id
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ), 0) AS ReturnedAmount,
        ISNULL(i.final_amount, 0) - ISNULL((
            SELECT SUM(pr.total_amount)
            FROM dbo.purchase_returns pr
            WHERE pr.import_id = i.import_id
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ), 0) AS AvailableAmount
    FROM dbo.imports i
    LEFT JOIN dbo.suppliers s ON s.supplier_id = i.supplier_id
    WHERE i.import_date BETWEEN @FromDate AND @ToDate
      AND ISNULL(i.status, N'') IN (N'Completed', N'Paid')
      AND (
            @Keyword = N''
            OR i.import_code LIKE N'%' + @Keyword + N'%'
            OR ISNULL(s.supplier_name, N'') LIKE N'%' + @Keyword + N'%'
          )
      AND EXISTS
      (
            SELECT 1
            FROM dbo.import_details id
            WHERE id.import_id = i.import_id
              AND ISNULL(id.quantity, 0) >
                  ISNULL((
                    SELECT SUM(prd.quantity)
                    FROM dbo.purchase_return_details prd
                    INNER JOIN dbo.purchase_returns pr ON pr.return_id = prd.return_id
                    WHERE prd.import_detail_id = id.import_detail_id
                      AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
                  ), 0)
      )
    ORDER BY i.import_date DESC, i.import_id DESC;
END
GO

IF OBJECT_ID(N'dbo.PurchaseReturns_GetImportDetailsForReturn', N'P') IS NOT NULL
    DROP PROCEDURE dbo.PurchaseReturns_GetImportDetailsForReturn;
GO
CREATE PROCEDURE dbo.PurchaseReturns_GetImportDetailsForReturn
    @ImportId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        id.import_detail_id AS ImportDetailId,
        id.import_id AS ImportId,
        id.product_id AS ProductId,
        p.product_code AS ProductCode,
        ISNULL(p.barcode, N'') AS Barcode,
        p.product_name AS ProductName,
        ISNULL(id.quantity, 0) AS ImportedQty,
        ISNULL((
            SELECT SUM(prd.quantity)
            FROM dbo.purchase_return_details prd
            INNER JOIN dbo.purchase_returns pr ON pr.return_id = prd.return_id
            WHERE prd.import_detail_id = id.import_detail_id
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ), 0) AS ReturnedQty,
        ISNULL(id.quantity, 0) - ISNULL((
            SELECT SUM(prd.quantity)
            FROM dbo.purchase_return_details prd
            INNER JOIN dbo.purchase_returns pr ON pr.return_id = prd.return_id
            WHERE prd.import_detail_id = id.import_detail_id
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ), 0) AS MaxReturnQty,
        CAST(0 AS INT) AS ReturnQty,
        ISNULL(id.import_price, 0) AS ImportPrice,
        CAST(0 AS DECIMAL(18,0)) AS ReturnAmount,
        CAST(N'' AS NVARCHAR(255)) AS Reason
    FROM dbo.import_details id
    INNER JOIN dbo.products p ON p.product_id = id.product_id
    WHERE id.import_id = @ImportId
      AND ISNULL(id.quantity, 0) > ISNULL((
            SELECT SUM(prd.quantity)
            FROM dbo.purchase_return_details prd
            INNER JOIN dbo.purchase_returns pr ON pr.return_id = prd.return_id
            WHERE prd.import_detail_id = id.import_detail_id
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
      ), 0)
    ORDER BY p.product_code, p.product_name;
END
GO

IF OBJECT_ID(N'dbo.PurchaseReturns_Insert', N'P') IS NOT NULL
    DROP PROCEDURE dbo.PurchaseReturns_Insert;
GO
CREATE PROCEDURE dbo.PurchaseReturns_Insert
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

    DECLARE @xml XML;
    SET @xml = TRY_CAST(@DetailsXml AS XML);

    IF @xml IS NULL
    BEGIN
        RAISERROR(N'Dữ liệu chi tiết trả hàng không hợp lệ.', 16, 1);
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
        RAISERROR(N'Chưa có sản phẩm trả nhà cung cấp.', 16, 1);
        RETURN;
    END

    IF EXISTS (SELECT 1 FROM @Detail WHERE Quantity <= 0)
    BEGIN
        RAISERROR(N'Số lượng trả phải lớn hơn 0.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.imports i
        WHERE i.import_id = @ImportId
          AND i.supplier_id = @SupplierId
          AND ISNULL(i.status, N'') IN (N'Completed', N'Paid')
    ) 
    BEGIN
        -- OK
        PRINT N'Valid import';
    END
    ELSE
    BEGIN
        RAISERROR(N'Phiếu nhập không hợp lệ hoặc chưa nhập kho.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM @Detail d
        LEFT JOIN dbo.import_details id ON id.import_detail_id = d.ImportDetailId
        WHERE id.import_detail_id IS NULL
           OR id.import_id <> @ImportId
           OR id.product_id <> d.ProductId
    )
    BEGIN
        RAISERROR(N'Sản phẩm trả không thuộc phiếu nhập đã chọn.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM @Detail d
        INNER JOIN dbo.import_details id ON id.import_detail_id = d.ImportDetailId
        OUTER APPLY
        (
            SELECT ISNULL(SUM(prd.quantity), 0) AS ReturnedQty
            FROM dbo.purchase_return_details prd
            INNER JOIN dbo.purchase_returns pr ON pr.return_id = prd.return_id
            WHERE prd.import_detail_id = id.import_detail_id
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ) r
        WHERE d.Quantity > (ISNULL(id.quantity, 0) - ISNULL(r.ReturnedQty, 0))
    )
    BEGIN
        RAISERROR(N'Số lượng trả vượt quá số lượng còn có thể trả của phiếu nhập.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM @Detail d
        INNER JOIN dbo.products p ON p.product_id = d.ProductId
        WHERE ISNULL(p.stock, 0) < d.Quantity
    )
    BEGIN
        RAISERROR(N'Tồn kho hiện tại không đủ để trả nhà cung cấp. Vui lòng kiểm tra lại kho.', 16, 1);
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

        DECLARE @Err NVARCHAR(4000);
        SET @Err = ERROR_MESSAGE();
        RAISERROR(@Err, 16, 1);
    END CATCH
END
GO

IF OBJECT_ID(N'dbo.SupplierPayments_GetDebt', N'P') IS NOT NULL
    DROP PROCEDURE dbo.SupplierPayments_GetDebt;
GO
CREATE PROCEDURE dbo.SupplierPayments_GetDebt
    @supplier_id INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TotalImport DECIMAL(18,0) = ISNULL((
        SELECT SUM(final_amount)
        FROM imports
        WHERE supplier_id = @supplier_id
          AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
    ), 0);

    DECLARE @TotalPaidAtImport DECIMAL(18,0) = ISNULL((
        SELECT SUM(paid_amount)
        FROM imports
        WHERE supplier_id = @supplier_id
          AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
    ), 0);

    DECLARE @TotalPaidAfter DECIMAL(18,0) = ISNULL((
        SELECT SUM(amount)
        FROM supplier_payments
        WHERE supplier_id = @supplier_id
    ), 0);

    DECLARE @TotalReturnToSupplier DECIMAL(18,0) = ISNULL((
        SELECT SUM(total_amount)
        FROM purchase_returns
        WHERE supplier_id = @supplier_id
          AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
    ), 0);

    SELECT (@TotalImport - @TotalPaidAtImport - @TotalPaidAfter - @TotalReturnToSupplier) AS CurrentDebt;
END
GO

IF OBJECT_ID(N'dbo.Suppliers_GetWithDebt', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Suppliers_GetWithDebt;
GO
CREATE PROCEDURE dbo.Suppliers_GetWithDebt
AS
BEGIN
    SET NOCOUNT ON;

    SELECT *
    FROM
    (
        SELECT 
            s.supplier_id AS SupplierId,
            ISNULL(s.supplier_name, '') AS SupplierName,
            ISNULL(s.phone, '') AS Phone,
            ISNULL(s.address, '') AS Address,
            ISNULL(s.email, '') AS Email,
            ISNULL(s.tax_code, '') AS TaxCode,
            ISNULL(s.is_active, 1) AS IsActive,
            (
                ISNULL((SELECT SUM(final_amount - paid_amount)
                        FROM imports
                        WHERE supplier_id = s.supplier_id
                          AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')), 0)
                - ISNULL((SELECT SUM(amount)
                          FROM supplier_payments
                          WHERE supplier_id = s.supplier_id), 0)
                - ISNULL((SELECT SUM(total_amount)
                          FROM purchase_returns
                          WHERE supplier_id = s.supplier_id
                            AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')), 0)
            ) AS CurrentDebt
        FROM dbo.suppliers s
    ) X
    WHERE X.CurrentDebt > 0
    ORDER BY X.SupplierName;
END
GO

IF OBJECT_ID(N'dbo.Report_GetInventoryMovement', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Report_GetInventoryMovement;
GO
CREATE PROCEDURE dbo.Report_GetInventoryMovement
    @FromDate DATETIME,
    @ToDate   DATETIME,
    @Keyword  NVARCHAR(200) = N''
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartDate DATETIME;
    DECLARE @EndDateExclusive DATETIME;

    SET @StartDate = CONVERT(DATE, @FromDate);
    SET @EndDateExclusive = DATEADD(DAY, 1, CONVERT(DATE, @ToDate));
    SET @Keyword = LTRIM(RTRIM(ISNULL(@Keyword, N'')));

    ;WITH Movements AS
    (
        -- Nhập mua từ nhà cung cấp: tăng kho
        SELECT
            id.product_id,
            i.import_date AS movement_date,
            CAST(ISNULL(id.base_quantity, id.quantity) AS DECIMAL(18, 3)) AS qty,
            CAST(ISNULL(id.total, ISNULL(id.import_price, 0) * ISNULL(id.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N'PURCHASE_IN' AS movement_type
        FROM dbo.import_details id
        INNER JOIN dbo.imports i ON i.import_id = id.import_id
        WHERE ISNULL(i.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
          AND i.import_date IS NOT NULL
          AND id.product_id IS NOT NULL

        UNION ALL

        -- Trả hàng nhà cung cấp: giảm kho
        SELECT
            prd.product_id,
            pr.return_date AS movement_date,
            -CAST(prd.quantity AS DECIMAL(18, 3)) AS qty,
            CAST(ISNULL(prd.total, ISNULL(prd.import_price, 0) * ISNULL(prd.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N'SUPPLIER_RETURN_OUT' AS movement_type
        FROM dbo.purchase_return_details prd
        INNER JOIN dbo.purchase_returns pr ON pr.return_id = prd.return_id
        WHERE ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
          AND pr.return_date IS NOT NULL
          AND prd.product_id IS NOT NULL

        UNION ALL

        -- Xuất bán: giảm kho
        SELECT
            oi.product_id,
            o.order_date AS movement_date,
            -CAST(ISNULL(oi.base_quantity, oi.quantity) AS DECIMAL(18, 3)) AS qty,
            CAST(ISNULL(oi.unit_price, 0) * ABS(ISNULL(oi.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N'SALES_OUT' AS movement_type
        FROM dbo.order_items oi
        INNER JOIN dbo.orders o ON o.order_id = oi.order_id
        WHERE ISNULL(o.status, N'') IN (N'Paid', N'Completed')
          AND ISNULL(o.order_type, N'') <> N'RETURN'
          AND o.order_date IS NOT NULL
          AND oi.product_id IS NOT NULL
          AND ISNULL(oi.quantity, 0) > 0

        UNION ALL

        -- Khách trả hàng: tăng kho
        SELECT
            oi.product_id,
            o.order_date AS movement_date,
            ABS(CAST(ISNULL(oi.base_quantity, oi.quantity) AS DECIMAL(18, 3))) AS qty,
            CAST(ISNULL(oi.unit_price, 0) * ABS(ISNULL(oi.quantity, 0)) AS DECIMAL(18, 0)) AS amount,
            N'RETURN_IN' AS movement_type
        FROM dbo.order_items oi
        INNER JOIN dbo.orders o ON o.order_id = oi.order_id
        WHERE ISNULL(o.status, N'') IN (N'Paid', N'Completed')
          AND ISNULL(o.order_type, N'') = N'RETURN'
          AND o.order_date IS NOT NULL
          AND oi.product_id IS NOT NULL

        UNION ALL

        -- Kiểm kê/chốt kho: tăng hoặc giảm theo cột difference
        SELECT
            icd.product_id,
            ic.check_date AS movement_date,
            CAST(icd.difference AS DECIMAL(18, 3)) AS qty,
            CAST(0 AS DECIMAL(18, 0)) AS amount,
            N'STOCKTAKE' AS movement_type
        FROM dbo.inventory_check_details icd
        INNER JOIN dbo.inventory_checks ic ON ic.check_id = icd.check_id
        WHERE ic.check_date IS NOT NULL
          AND icd.product_id IS NOT NULL
          AND ISNULL(icd.difference, 0) <> 0
    ),
    PeriodSummary AS
    (
        SELECT
            product_id,
            SUM(CASE WHEN movement_type = N'PURCHASE_IN'          AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS PurchaseInQty,
            SUM(CASE WHEN movement_type = N'SUPPLIER_RETURN_OUT'  AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN ABS(qty) ELSE 0 END) AS SupplierReturnOutQty,
            SUM(CASE WHEN movement_type = N'SALES_OUT'            AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN ABS(qty) ELSE 0 END) AS SalesOutQty,
            SUM(CASE WHEN movement_type = N'RETURN_IN'            AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS ReturnInQty,
            SUM(CASE WHEN movement_type = N'STOCKTAKE'            AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS StocktakeAdjustQty,
            SUM(CASE WHEN movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN qty ELSE 0 END) AS NetPeriodQty,
            SUM(CASE WHEN movement_type = N'PURCHASE_IN'          AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS PurchaseInValue,
            SUM(CASE WHEN movement_type = N'SUPPLIER_RETURN_OUT'  AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS SupplierReturnOutValue,
            SUM(CASE WHEN movement_type = N'SALES_OUT'            AND movement_date >= @StartDate AND movement_date < @EndDateExclusive THEN amount ELSE 0 END) AS SalesOutValue
        FROM Movements
        GROUP BY product_id
    ),
    AfterPeriodSummary AS
    (
        SELECT
            product_id,
            SUM(qty) AS NetAfterPeriodQty
        FROM Movements
        WHERE movement_date >= @EndDateExclusive
        GROUP BY product_id
    )
    SELECT
        p.product_id AS ProductId,
        p.product_code AS ProductCode,
        ISNULL(p.barcode, N'') AS Barcode,
        p.product_name AS ProductName,
        ISNULL(c.category_name, N'') AS CategoryName,
        ISNULL(u.unit_name, N'') AS UnitName,

        CAST(ISNULL(p.stock, 0) - ISNULL(a.NetAfterPeriodQty, 0) - ISNULL(ps.NetPeriodQty, 0) AS DECIMAL(18, 3)) AS OpeningStock,
        CAST(ISNULL(ps.PurchaseInQty, 0) AS DECIMAL(18, 3)) AS PurchaseInQty,
        CAST(ISNULL(ps.ReturnInQty, 0) AS DECIMAL(18, 3)) AS ReturnInQty,
        CAST(ISNULL(ps.SupplierReturnOutQty, 0) AS DECIMAL(18, 3)) AS SupplierReturnOutQty,
        CAST(ISNULL(ps.StocktakeAdjustQty, 0) AS DECIMAL(18, 3)) AS StocktakeAdjustQty,
        CAST(ISNULL(ps.SalesOutQty, 0) AS DECIMAL(18, 3)) AS SalesOutQty,
        CAST(ISNULL(p.stock, 0) - ISNULL(a.NetAfterPeriodQty, 0) AS DECIMAL(18, 3)) AS ClosingStock,
        CAST(ISNULL(p.stock, 0) AS DECIMAL(18, 3)) AS CurrentStock,

        CAST(ISNULL(ps.PurchaseInValue, 0) AS DECIMAL(18, 0)) AS PurchaseInValue,
        CAST(ISNULL(ps.SupplierReturnOutValue, 0) AS DECIMAL(18, 0)) AS SupplierReturnOutValue,
        CAST(ISNULL(ps.SalesOutValue, 0) AS DECIMAL(18, 0)) AS SalesOutValue,
        CAST((ISNULL(p.stock, 0) - ISNULL(a.NetAfterPeriodQty, 0)) * ISNULL(p.import_price, 0) AS DECIMAL(18, 0)) AS ClosingCostValue
    FROM dbo.products p
    LEFT JOIN dbo.categories c ON c.category_id = p.category_id
    LEFT JOIN dbo.Units u ON u.unit_id = p.unit_id
    LEFT JOIN PeriodSummary ps ON ps.product_id = p.product_id
    LEFT JOIN AfterPeriodSummary a ON a.product_id = p.product_id
    WHERE ISNULL(p.is_active, 1) = 1
      AND (
            @Keyword = N''
            OR p.product_code LIKE N'%' + @Keyword + N'%'
            OR ISNULL(p.barcode, N'') LIKE N'%' + @Keyword + N'%'
            OR p.product_name LIKE N'%' + @Keyword + N'%'
          )
    ORDER BY p.product_code, p.product_name;
END
GO

IF OBJECT_ID(N'dbo.__AppSqlMigrations', N'U') IS NOT NULL
BEGIN
    IF NOT EXISTS (SELECT 1 FROM dbo.__AppSqlMigrations WHERE MigrationId = N'2026-06-12-purchase-return-supplier')
    BEGIN
        INSERT INTO dbo.__AppSqlMigrations(MigrationId, ScriptUrl, Sha256, AppliedAt)
        VALUES(N'2026-06-12-purchase-return-supplier', NULL, NULL, GETDATE());
    END
END
GO

--------------------------------------------------------------------------------
-- PHẦN 3: 2026-06-12-purchase-return-history
--------------------------------------------------------------------------------

-- =========================================================
-- MyShop - Lịch sử trả hàng nhà cung cấp
-- MigrationId: 2026-06-12-purchase-return-history
-- Phụ thuộc: 2026-06-12-purchase-return-supplier
-- =========================================================

IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NULL
BEGIN
    RAISERROR(N'Chưa có bảng purchase_returns. Vui lòng chạy migration trả hàng NCC trước.', 16, 1);
    RETURN;
END
GO

IF OBJECT_ID(N'dbo.PurchaseReturnHistory_GetReturns', N'P') IS NOT NULL
    DROP PROCEDURE dbo.PurchaseReturnHistory_GetReturns;
GO
CREATE PROCEDURE dbo.PurchaseReturnHistory_GetReturns
    @FromDate DATETIME,
    @ToDate DATETIME,
    @Keyword NVARCHAR(200) = N''
AS
BEGIN
    SET NOCOUNT ON;

    SET @Keyword = LTRIM(RTRIM(ISNULL(@Keyword, N'')));

    SELECT
        pr.return_id AS ReturnId,
        pr.return_code AS ReturnCode,
        pr.import_id AS ImportId,
        ISNULL(i.import_code, N'') AS ImportCode,
        pr.supplier_id AS SupplierId,
        ISNULL(s.supplier_name, N'') AS SupplierName,
        pr.employee_id AS EmployeeId,
        ISNULL(e.name, ISNULL(u.Username, N'')) AS EmployeeName,
        pr.return_date AS ReturnDate,
        ISNULL(pr.total_amount, 0) AS TotalAmount,
        ISNULL(pr.note, N'') AS Note,
        ISNULL(pr.status, N'') AS Status,
        CASE
            WHEN ISNULL(pr.status, N'') IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy') THEN N'Đã hủy'
            ELSE N'Hoàn tất'
        END AS StatusText
    FROM dbo.purchase_returns pr
    LEFT JOIN dbo.imports i ON i.import_id = pr.import_id
    LEFT JOIN dbo.suppliers s ON s.supplier_id = pr.supplier_id
    LEFT JOIN dbo.employees e ON e.employee_id = pr.employee_id
    LEFT JOIN dbo.Users u ON u.employee_id = pr.employee_id
    WHERE pr.return_date BETWEEN @FromDate AND @ToDate
      AND (
            @Keyword = N''
            OR pr.return_code LIKE N'%' + @Keyword + N'%'
            OR ISNULL(i.import_code, N'') LIKE N'%' + @Keyword + N'%'
            OR ISNULL(s.supplier_name, N'') LIKE N'%' + @Keyword + N'%'
            OR ISNULL(pr.note, N'') LIKE N'%' + @Keyword + N'%'
          )
    ORDER BY pr.return_date DESC, pr.return_id DESC;
END
GO

IF OBJECT_ID(N'dbo.PurchaseReturnHistory_GetReturnDetails', N'P') IS NOT NULL
    DROP PROCEDURE dbo.PurchaseReturnHistory_GetReturnDetails;
GO
CREATE PROCEDURE dbo.PurchaseReturnHistory_GetReturnDetails
    @ReturnId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        prd.return_detail_id AS ReturnDetailId,
        prd.return_id AS ReturnId,
        prd.import_detail_id AS ImportDetailId,
        prd.product_id AS ProductId,
        ISNULL(p.product_code, N'') AS ProductCode,
        ISNULL(p.barcode, N'') AS Barcode,
        ISNULL(p.product_name, N'') AS ProductName,
        ISNULL(prd.quantity, 0) AS Quantity,
        ISNULL(prd.import_price, 0) AS ImportPrice,
        ISNULL(prd.total, ISNULL(prd.import_price, 0) * ISNULL(prd.quantity, 0)) AS Total,
        ISNULL(prd.reason, N'') AS Reason
    FROM dbo.purchase_return_details prd
    LEFT JOIN dbo.products p ON p.product_id = prd.product_id
    WHERE prd.return_id = @ReturnId
    ORDER BY p.product_code, p.product_name;
END
GO

IF OBJECT_ID(N'dbo.PurchaseReturnHistory_CancelReturn', N'P') IS NOT NULL
    DROP PROCEDURE dbo.PurchaseReturnHistory_CancelReturn;
GO
CREATE PROCEDURE dbo.PurchaseReturnHistory_CancelReturn
    @ReturnId INT,
    @EmployeeId INT,
    @Reason NVARCHAR(500) = N''
AS
BEGIN
    SET NOCOUNT ON;

    SET @Reason = LTRIM(RTRIM(ISNULL(@Reason, N'')));
    IF @Reason = N'' SET @Reason = N'Hủy phiếu trả NCC';

    IF NOT EXISTS (SELECT 1 FROM dbo.purchase_returns WHERE return_id = @ReturnId)
    BEGIN
        RAISERROR(N'Không tìm thấy phiếu trả NCC.', 16, 1);
        RETURN;
    END

    IF EXISTS (
        SELECT 1
        FROM dbo.purchase_returns
        WHERE return_id = @ReturnId
          AND ISNULL(status, N'') IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
    )
    BEGIN
        RAISERROR(N'Phiếu trả NCC này đã bị hủy trước đó.', 16, 1);
        RETURN;
    END

    BEGIN TRY
        BEGIN TRANSACTION;

        -- Đảo nghiệp vụ trả NCC: cộng lại tồn kho.
        UPDATE p
        SET p.stock = ISNULL(p.stock, 0) + ISNULL(d.quantity, 0)
        FROM dbo.products p
        INNER JOIN dbo.purchase_return_details d ON d.product_id = p.product_id
        WHERE d.return_id = @ReturnId;

        -- Đánh dấu hủy. Công nợ NCC tự cộng lại vì các báo cáo công nợ loại trừ phiếu Cancelled.
        UPDATE dbo.purchase_returns
        SET status = N'Cancelled',
            note = ISNULL(note, N'') +
                   CASE WHEN ISNULL(note, N'') = N'' THEN N'' ELSE CHAR(13) + CHAR(10) END +
                   N'[ĐÃ HỦY ' + CONVERT(NVARCHAR(19), GETDATE(), 120) + N'] ' + @Reason
        WHERE return_id = @ReturnId;

        COMMIT TRANSACTION;

        SELECT 1 AS Result;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        DECLARE @Err NVARCHAR(4000);
        SET @Err = ERROR_MESSAGE();
        RAISERROR(@Err, 16, 1);
    END CATCH
END
GO

--------------------------------------------------------------------------------
-- PHẦN 4: 2026-06-12-report-overview-profit-purchase-return
--------------------------------------------------------------------------------

-- =========================================================
-- MyShop - Sửa báo cáo tổng quan: tính trả hàng NCC và lợi nhuận đúng hơn
-- MigrationId: 2026-06-12-report-overview-profit-purchase-return
-- =========================================================

IF OBJECT_ID(N'dbo.Report_GetOverview', N'P') IS NOT NULL
    DROP PROCEDURE dbo.Report_GetOverview;
GO

CREATE PROCEDURE dbo.Report_GetOverview
    @FromDate DATETIME,
    @ToDate DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @StartDate DATETIME = @FromDate;
    DECLARE @EndDate DATETIME = @ToDate;

    DECLARE @GrossSales DECIMAL(18,0) = 0;
    DECLARE @CustomerReturnAmount DECIMAL(18,0) = 0;
    DECLARE @NetRevenue DECIMAL(18,0) = 0;

    DECLARE @TotalPurchase DECIMAL(18,0) = 0;
    DECLARE @PurchaseReturnAmount DECIMAL(18,0) = 0;
    DECLARE @NetPurchase DECIMAL(18,0) = 0;

    DECLARE @OrderCount INT = 0;
    DECLARE @CostOfGoodsSold DECIMAL(18,0) = 0;
    DECLARE @GrossProfit DECIMAL(18,0) = 0;

    DECLARE @TotalDebtCustomer DECIMAL(18,0) = 0;
    DECLARE @TotalDebtSupplier DECIMAL(18,0) = 0;

    -- Doanh thu bán ra, không tính phiếu trả hàng khách
    SELECT @GrossSales = ISNULL(SUM(ISNULL(final_amount, 0)), 0)
    FROM dbo.orders
    WHERE order_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'') IN (N'Completed', N'Paid', N'Partial')
      AND ISNULL(order_type, N'') <> N'RETURN';

    -- Khách trả hàng: giảm doanh thu
    SELECT @CustomerReturnAmount = ISNULL(SUM(ABS(ISNULL(final_amount, 0))), 0)
    FROM dbo.orders
    WHERE order_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'') IN (N'Completed', N'Paid', N'Partial')
      AND ISNULL(order_type, N'') = N'RETURN';

    SET @NetRevenue = ISNULL(@GrossSales, 0) - ISNULL(@CustomerReturnAmount, 0);

    -- Tổng nhập hàng trong kỳ
    SELECT @TotalPurchase = ISNULL(SUM(ISNULL(final_amount, 0)), 0)
    FROM dbo.imports
    WHERE import_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy');

    -- Trả hàng NCC trong kỳ: giảm chi phí nhập/công nợ NCC
    IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NOT NULL
    BEGIN
        SELECT @PurchaseReturnAmount = ISNULL(SUM(ISNULL(total_amount, 0)), 0)
        FROM dbo.purchase_returns
        WHERE return_date BETWEEN @StartDate AND @EndDate
          AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy');
    END

    SET @NetPurchase = ISNULL(@TotalPurchase, 0) - ISNULL(@PurchaseReturnAmount, 0);
    IF @NetPurchase < 0 SET @NetPurchase = 0;

    -- Số hóa đơn bán trong kỳ, không tính phiếu trả hàng
    SELECT @OrderCount = COUNT(*)
    FROM dbo.orders
    WHERE order_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(status, N'') IN (N'Completed', N'Paid', N'Partial')
      AND ISNULL(order_type, N'') <> N'RETURN';

    -- Giá vốn hàng bán: bán ra trừ lại phần khách trả hàng
    SELECT @CostOfGoodsSold = ISNULL(SUM(
        CASE 
            WHEN ISNULL(o.order_type, N'') = N'RETURN' THEN 
                -1 * ISNULL(oi.cost_price, ISNULL(p.import_price, 0)) * ABS(ISNULL(oi.base_quantity, oi.quantity))
            ELSE
                ISNULL(oi.cost_price, ISNULL(p.import_price, 0)) * ABS(ISNULL(oi.base_quantity, oi.quantity))
        END
    ), 0)
    FROM dbo.order_items oi
    INNER JOIN dbo.orders o ON o.order_id = oi.order_id
    LEFT JOIN dbo.products p ON p.product_id = oi.product_id
    WHERE o.order_date BETWEEN @StartDate AND @EndDate
      AND ISNULL(o.status, N'') IN (N'Completed', N'Paid', N'Partial')
      AND oi.product_id IS NOT NULL;

    IF @CostOfGoodsSold < 0 SET @CostOfGoodsSold = 0;

    SET @GrossProfit = ISNULL(@NetRevenue, 0) - ISNULL(@CostOfGoodsSold, 0);

    -- Công nợ khách hàng hiện tại
    SELECT @TotalDebtCustomer = ISNULL(SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0)), 0)
    FROM dbo.orders
    WHERE ISNULL(status, N'') IN (N'Completed', N'Partial')
      AND ISNULL(final_amount, 0) > ISNULL(paid_amount, 0)
      AND ISNULL(order_type, N'') <> N'RETURN';

    -- Công nợ NCC hiện tại = nhập còn nợ - đã chi - trả NCC hiệu lực
    SELECT @TotalDebtSupplier =
        ISNULL((
            SELECT SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0))
            FROM dbo.imports
            WHERE ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ), 0)
        -
        ISNULL((
            SELECT SUM(ISNULL(amount, 0))
            FROM dbo.supplier_payments
        ), 0);

    IF OBJECT_ID(N'dbo.purchase_returns', N'U') IS NOT NULL
    BEGIN
        SELECT @TotalDebtSupplier = @TotalDebtSupplier - ISNULL(SUM(ISNULL(total_amount, 0)), 0)
        FROM dbo.purchase_returns
        WHERE ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy');
    END

    IF @TotalDebtSupplier < 0 SET @TotalDebtSupplier = 0;

    SELECT
        ISNULL(@NetRevenue, 0) AS TotalRevenue,
        ISNULL(@NetPurchase, 0) AS TotalCost,
        ISNULL(@OrderCount, 0) AS OrderCount,
        ISNULL(@GrossProfit, 0) AS GrossProfit,
        ISNULL(@TotalDebtCustomer, 0) AS TotalDebtCustomer,
        ISNULL(@TotalDebtSupplier, 0) AS TotalDebtSupplier,

        ISNULL(@GrossSales, 0) AS GrossSales,
        ISNULL(@CustomerReturnAmount, 0) AS CustomerReturnAmount,
        ISNULL(@TotalPurchase, 0) AS TotalPurchase,
        ISNULL(@PurchaseReturnAmount, 0) AS PurchaseReturnAmount,
        ISNULL(@CostOfGoodsSold, 0) AS CostOfGoodsSold;
END
GO