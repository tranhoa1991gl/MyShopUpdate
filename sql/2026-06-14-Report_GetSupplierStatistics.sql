CREATE PROCEDURE [dbo].[Report_GetSupplierStatistics]
    @FromDate DATETIME,
    @ToDate DATETIME
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP 50
        s.supplier_id AS SupplierId,
        ISNULL(s.supplier_name, N'Không xác định') AS SupplierName,
        ISNULL(s.phone, '') AS Phone,
        
        -- Tổng tiền hàng đã nhập trong kỳ
        ISNULL(SUM(i.final_amount), 0) AS TotalImportAmount,

        -- Tổng tiền trả hàng NCC trong kỳ
        ISNULL((
            SELECT SUM(pr.total_amount) 
            FROM dbo.purchase_returns pr 
            WHERE pr.supplier_id = s.supplier_id 
              AND pr.return_date BETWEEN @FromDate AND @ToDate 
              AND ISNULL(pr.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
        ), 0) AS TotalReturnAmount,

        -- Công nợ hiện tại (Lũy kế toàn thời gian)
        (
            ISNULL((SELECT SUM(final_amount - paid_amount) FROM dbo.imports WHERE supplier_id = s.supplier_id AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')), 0)
            - ISNULL((SELECT SUM(amount) FROM dbo.supplier_payments WHERE supplier_id = s.supplier_id), 0)
            - ISNULL((SELECT SUM(total_amount) FROM dbo.purchase_returns WHERE supplier_id = s.supplier_id AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')), 0)
        ) AS CurrentDebt

    FROM dbo.suppliers s
    LEFT JOIN dbo.imports i ON s.supplier_id = i.supplier_id 
        AND i.import_date BETWEEN @FromDate AND @ToDate
        AND ISNULL(i.status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')
    GROUP BY s.supplier_id, s.supplier_name, s.phone
    HAVING ISNULL(SUM(i.final_amount), 0) > 0 OR (
        ISNULL((SELECT SUM(final_amount - paid_amount) FROM dbo.imports WHERE supplier_id = s.supplier_id AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')), 0)
        - ISNULL((SELECT SUM(amount) FROM dbo.supplier_payments WHERE supplier_id = s.supplier_id), 0)
        - ISNULL((SELECT SUM(total_amount) FROM dbo.purchase_returns WHERE supplier_id = s.supplier_id AND ISNULL(status, N'') NOT IN (N'Cancelled', N'Canceled', N'Đã hủy', N'Hủy')), 0)
    ) > 0
    ORDER BY TotalImportAmount DESC
END
GO