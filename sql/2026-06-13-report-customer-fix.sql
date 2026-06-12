SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

ALTER PROCEDURE [dbo].[Customer_GetTop]
    @TopCount INT = 20,
    @FromDate DATETIME = NULL,
    @ToDate DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (@TopCount)
        c.customer_id AS CustomerId,
        c.name AS CustomerName,
        c.phone AS Phone,
        c.email AS Email,
        c.address AS Address,
        c.points AS Points,
        c.created_at AS CreatedAt, -- [MỚI BỔ SUNG] Lấy ngày tạo tài khoản

        COUNT(o.order_id) AS TotalOrders,

        -- Tính doanh số thực thu
        ISNULL(SUM(ISNULL(o.final_amount, o.total_amount)), 0) AS TotalRevenue,

        MIN(o.order_date) AS FirstOrderDate,
        MAX(o.order_date) AS LastOrderDate,

        -- [MỚI BỔ SUNG] Tính công nợ tổng của khách hàng
        (
            ISNULL((SELECT SUM(ISNULL(final_amount, 0) - ISNULL(paid_amount, 0)) 
                    FROM orders 
                    WHERE customer_id = c.customer_id AND ISNULL(status, '') != 'Cancelled'), 0)
            - 
            ISNULL((SELECT SUM(ISNULL(amount, 0)) 
                    FROM customer_payments 
                    WHERE customer_id = c.customer_id), 0)
        ) AS CurrentDebt

    FROM customers c
    JOIN orders o ON c.customer_id = o.customer_id
    WHERE
        (@FromDate IS NULL OR o.order_date >= @FromDate)
        AND (@ToDate IS NULL OR o.order_date < DATEADD(DAY, 1, @ToDate))
    GROUP BY
        c.customer_id,
        c.name,
        c.phone,
        c.email,
        c.address,
        c.points,
        c.created_at -- Bắt buộc phải thêm vào GROUP BY
    ORDER BY TotalRevenue DESC;
END
GO