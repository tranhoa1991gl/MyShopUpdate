SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

/*
    Bản cũ reset các bảng rỗng về identity 0. SQL Server có thể cấp ID 0
    cho khách/hóa đơn đầu tiên. Form lại dùng ID > 0 làm dấu hiệu thành công,
    khiến người dùng bấm lần hai và tạo một giao dịch trùng hoàn chỉnh.

    Chỉ dọn order_id = 0 khi tìm được một hóa đơn ID dương giống tuyệt đối
    về phần đầu + tập mặt hàng và được tạo trong vòng 30 giây.
*/
DECLARE @ZeroOrderCode VARCHAR(20);
DECLARE @DuplicateOrderId INT;

SELECT @ZeroOrderCode = order_code
FROM dbo.orders WITH (UPDLOCK, HOLDLOCK)
WHERE order_id = 0;

IF @ZeroOrderCode IS NOT NULL
BEGIN
    SELECT TOP (1) @DuplicateOrderId = candidate.order_id
    FROM dbo.orders zero_order
    INNER JOIN dbo.orders candidate
        ON candidate.order_id > 0
       AND ISNULL(candidate.customer_id, -1) = ISNULL(zero_order.customer_id, -1)
       AND ISNULL(candidate.employee_id, -1) = ISNULL(zero_order.employee_id, -1)
       AND ISNULL(candidate.cashier_id, -1) = ISNULL(zero_order.cashier_id, -1)
       AND ISNULL(candidate.total_amount, 0) = ISNULL(zero_order.total_amount, 0)
       AND ISNULL(candidate.discount, 0) = ISNULL(zero_order.discount, 0)
       AND ISNULL(candidate.vat_amount, 0) = ISNULL(zero_order.vat_amount, 0)
       AND ISNULL(candidate.final_amount, 0) = ISNULL(zero_order.final_amount, 0)
       AND ISNULL(candidate.paid_amount, 0) = ISNULL(zero_order.paid_amount, 0)
       AND ISNULL(candidate.status, N'') = ISNULL(zero_order.status, N'')
       AND ISNULL(candidate.payment_method, N'') = ISNULL(zero_order.payment_method, N'')
       AND ISNULL(candidate.order_type, '') = ISNULL(zero_order.order_type, '')
       AND ABS(DATEDIFF(SECOND, zero_order.order_date, candidate.order_date)) <= 30
    WHERE zero_order.order_id = 0
      AND zero_order.order_type = 'SALE'
      AND NOT EXISTS
      (
          SELECT product_id, ISNULL(product_variant_id, 0), quantity,
                 ISNULL(gift_quantity, 0), unit_price, ISNULL(serial_number, N''), COUNT_BIG(*)
          FROM dbo.order_items
          WHERE order_id = zero_order.order_id
          GROUP BY product_id, ISNULL(product_variant_id, 0), quantity,
                   ISNULL(gift_quantity, 0), unit_price, ISNULL(serial_number, N'')
          EXCEPT
          SELECT product_id, ISNULL(product_variant_id, 0), quantity,
                 ISNULL(gift_quantity, 0), unit_price, ISNULL(serial_number, N''), COUNT_BIG(*)
          FROM dbo.order_items
          WHERE order_id = candidate.order_id
          GROUP BY product_id, ISNULL(product_variant_id, 0), quantity,
                   ISNULL(gift_quantity, 0), unit_price, ISNULL(serial_number, N'')
      )
      AND NOT EXISTS
      (
          SELECT product_id, ISNULL(product_variant_id, 0), quantity,
                 ISNULL(gift_quantity, 0), unit_price, ISNULL(serial_number, N''), COUNT_BIG(*)
          FROM dbo.order_items
          WHERE order_id = candidate.order_id
          GROUP BY product_id, ISNULL(product_variant_id, 0), quantity,
                   ISNULL(gift_quantity, 0), unit_price, ISNULL(serial_number, N'')
          EXCEPT
          SELECT product_id, ISNULL(product_variant_id, 0), quantity,
                 ISNULL(gift_quantity, 0), unit_price, ISNULL(serial_number, N''), COUNT_BIG(*)
          FROM dbo.order_items
          WHERE order_id = zero_order.order_id
          GROUP BY product_id, ISNULL(product_variant_id, 0), quantity,
                   ISNULL(gift_quantity, 0), unit_price, ISNULL(serial_number, N'')
      )
      AND NOT EXISTS
      (
          SELECT 1 FROM dbo.product_serials WHERE order_id = zero_order.order_id
      )
      AND
      (
          OBJECT_ID(N'dbo.customer_wallet_transactions', N'U') IS NULL
          OR NOT EXISTS
          (
              SELECT 1 FROM dbo.customer_wallet_transactions
              WHERE order_id = zero_order.order_id
          )
      )
    ORDER BY candidate.order_date, candidate.order_id;
END;

IF @DuplicateOrderId IS NOT NULL
BEGIN
    /* Hoàn lại điểm của bản trùng ID 0. */
    UPDATE customer
    SET points = ISNULL(customer.points, 0)
               + ISNULL(zero_order.points_used, 0)
               - ISNULL(zero_order.points_earned, 0)
    FROM dbo.customers customer
    INNER JOIN dbo.orders zero_order ON zero_order.customer_id = customer.customer_id
    WHERE zero_order.order_id = 0;

    /* Hoàn lại tồn cha và tồn từng biến thể đúng một lần. */
    UPDATE product
    SET stock = ISNULL(product.stock, 0) + movement.quantity_to_restore
    FROM dbo.products product
    INNER JOIN
    (
        SELECT product_id,
               SUM(CASE WHEN quantity < 0
                        THEN quantity - ISNULL(gift_quantity, 0)
                        ELSE quantity + ISNULL(gift_quantity, 0) END) AS quantity_to_restore
        FROM dbo.order_items
        WHERE order_id = 0
        GROUP BY product_id
    ) movement ON movement.product_id = product.product_id;

    IF OBJECT_ID(N'dbo.product_variants', N'U') IS NOT NULL
    BEGIN
        UPDATE variant
        SET stock_base_qty = ISNULL(variant.stock_base_qty, 0) + movement.quantity_to_restore,
            updated_at = GETDATE()
        FROM dbo.product_variants variant
        INNER JOIN
        (
            SELECT product_variant_id,
                   SUM(CASE WHEN quantity < 0
                            THEN quantity - ISNULL(gift_quantity, 0)
                            ELSE quantity + ISNULL(gift_quantity, 0) END) AS quantity_to_restore
            FROM dbo.order_items
            WHERE order_id = 0
              AND product_variant_id IS NOT NULL
            GROUP BY product_variant_id
        ) movement ON movement.product_variant_id = variant.variant_id;
    END;

    /* Phiếu thu của hóa đơn trùng được giữ lịch sử nhưng đánh dấu đã xóa. */
    IF OBJECT_ID(N'dbo.cashbook_entries', N'U') IS NOT NULL
    BEGIN
        UPDATE dbo.cashbook_entries
        SET is_deleted = 1,
            updated_at = GETDATE()
        WHERE reference_code = N'BH:' + @ZeroOrderCode
          AND ISNULL(is_deleted, 0) = 0;
    END;

    DELETE FROM dbo.order_items WHERE order_id = 0;
    DELETE FROM dbo.orders WHERE order_id = 0;
END;

/*
    Xóa khách ID 0 chỉ khi không còn bất kỳ giao dịch nào tham chiếu đến nó
    và đã có khách ID dương cùng tên + số điện thoại. Đây là bản ghi được tạo
    bởi lần bấm đầu thất bại, không phải dữ liệu khách độc lập.
*/
IF EXISTS
(
    SELECT 1
    FROM dbo.customers zero_customer
    WHERE zero_customer.customer_id = 0
      AND EXISTS
      (
          SELECT 1
          FROM dbo.customers positive_customer
          WHERE positive_customer.customer_id > 0
            AND LTRIM(RTRIM(ISNULL(positive_customer.name, N''))) = LTRIM(RTRIM(ISNULL(zero_customer.name, N'')))
            AND LTRIM(RTRIM(ISNULL(positive_customer.phone, N''))) = LTRIM(RTRIM(ISNULL(zero_customer.phone, N'')))
      )
      AND NOT EXISTS (SELECT 1 FROM dbo.orders WHERE customer_id = 0)
      AND NOT EXISTS (SELECT 1 FROM dbo.customer_payments WHERE customer_id = 0)
      AND
      (
          OBJECT_ID(N'dbo.customer_wallet_transactions', N'U') IS NULL
          OR NOT EXISTS (SELECT 1 FROM dbo.customer_wallet_transactions WHERE customer_id = 0)
      )
      AND
      (
          OBJECT_ID(N'dbo.customer_debt_adjustments', N'U') IS NULL
          OR NOT EXISTS (SELECT 1 FROM dbo.customer_debt_adjustments WHERE customer_id = 0)
      )
)
    DELETE FROM dbo.customers WHERE customer_id = 0;

/* Bảo đảm các lần chèn tiếp theo không quay lại ID 0. */
IF NOT EXISTS (SELECT 1 FROM dbo.orders WHERE order_id <= 0)
   AND IDENT_CURRENT(N'dbo.orders') < 1
    DBCC CHECKIDENT ('dbo.orders', RESEED, 1) WITH NO_INFOMSGS;

IF NOT EXISTS (SELECT 1 FROM dbo.customers WHERE customer_id <= 0)
   AND IDENT_CURRENT(N'dbo.customers') < 1
    DBCC CHECKIDENT ('dbo.customers', RESEED, 1) WITH NO_INFOMSGS;

COMMIT TRANSACTION;
