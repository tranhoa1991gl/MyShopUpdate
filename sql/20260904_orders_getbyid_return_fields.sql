SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Kiểm tra schema nền theo cách tương thích rộng hơn.
-- Dùng sys.columns + RAISERROR thay cho COL_LENGTH/THROW để tránh lỗi parser
-- trên một số môi trường SQL Server/SSMS khi chạy migration thủ công.
IF OBJECT_ID(N'dbo.orders', N'U') IS NULL
BEGIN
    RAISERROR(N'Không tìm thấy bảng dbo.orders.', 16, 1);
    RETURN;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.orders', N'U')
      AND name = N'order_type'
)
BEGIN
    RAISERROR(N'Thiếu cột dbo.orders.order_type. Hãy cập nhật schema nền trước.', 16, 1);
    RETURN;
END;

IF NOT EXISTS
(
    SELECT 1
    FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.orders', N'U')
      AND name = N'original_order_id'
)
BEGIN
    RAISERROR(N'Thiếu cột dbo.orders.original_order_id. Hãy cập nhật schema nền trước.', 16, 1);
    RETURN;
END;
GO

CREATE OR ALTER PROCEDURE [dbo].[Orders_GetById]
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        o.order_id AS OrderId,
        o.order_code AS OrderCode,
        o.order_date AS OrderDate,
        o.total_amount AS TotalAmount,
        o.discount AS Discount,
        o.vat_amount AS VatAmount,
        o.final_amount AS FinalAmount,
        o.paid_amount AS PaidAmount,
        o.status AS Status,
        o.note AS Note,
        o.payment_method AS PaymentMethod,
        o.order_type AS OrderType,
        o.original_order_id AS OriginalOrderId,

        -- Thông tin khách hàng
        o.customer_id AS CustomerId,
        ISNULL(c.name, N'Khách lẻ') AS CustomerName,
        ISNULL(c.phone, '') AS Phone,

        -- Thông tin nhân viên tư vấn (Sales)
        o.employee_id AS EmployeeId,
        ISNULL(e.name, N'Admin') AS EmployeeName,

        -- Thông tin người thu ngân (Đứng máy)
        o.cashier_id AS CashierId,
        ISNULL(cashier.name, N'Admin') AS CashierName,

        ISNULL(o.points_earned, 0) AS PointsEarned,
        ISNULL(o.points_used, 0) AS PointsUsed

    FROM dbo.orders o
    LEFT JOIN dbo.customers c ON o.customer_id = c.customer_id
    LEFT JOIN dbo.employees e ON o.employee_id = e.employee_id
    LEFT JOIN dbo.employees cashier ON o.cashier_id = cashier.employee_id
    WHERE o.order_id = @OrderId;
END
GO
