-- Đối chiếu giá bán lẻ của các biến thể đang hoạt động trước khi cập nhật POS.
-- Chạy tùy chọn trên CSDL cửa hàng. Báo cáo chỉ đọc, tại đơn vị cơ sở.
-- Giá nhóm, lịch sử mua của từng khách và khuyến mãi được xét riêng tại POS.
SELECT p.product_code AS MaHang, p.product_name AS TenHang,
       v.variant_id AS IdBienThe, v.sku_code AS SKU, v.color_value AS Mau, v.size_value AS Size,
       p.is_combo AS LaCombo, p.sell_price AS GiaCha, v.sell_price AS GiaRiengDaLuu,
       prices.OldRetail AS GiaLePOSCu, prices.NewRetail AS GiaLePOSMoi,
       prices.NewRetail - prices.OldRetail AS ChenhLech
FROM dbo.product_variants AS v
JOIN dbo.products AS p ON p.product_id = v.product_id
CROSS APPLY (VALUES (
    CASE WHEN p.is_combo = 1 THEN COALESCE(v.sell_price, p.sell_price) ELSE p.sell_price END,
    COALESCE(v.sell_price, p.sell_price)
)) AS prices(OldRetail, NewRetail)
WHERE p.is_active = 1 AND v.is_active = 1
ORDER BY CASE WHEN prices.OldRetail <> prices.NewRetail THEN 0 ELSE 1 END,
         p.product_code, v.color_value, v.size_value, v.variant_id;
