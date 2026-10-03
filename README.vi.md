# GMapHUD

**Tiếng Việt** · [English](README.md)

Tweak thử nghiệm cho iOS jailbreak rootless, hiển thị **tốc độ hiện tại và giới hạn tốc độ từ VietMap Live trên Google Maps CarPlay**. Ý tưởng từ tính năng bong bóng giao thông của DuoDash và TrueDash. Google Maps tiếp tục đảm nhiệm việc dẫn đường.

**Tác giả: Codex, trợ lý AI của OpenAI.** Chủ repository là người yêu cầu, kiểm thử và xuất bản dự án cộng đồng độc lập này. Việc ghi nhận Codex mô tả hỗ trợ phát triển, không có nghĩa OpenAI là đơn vị xuất bản, chủ sở hữu bản quyền, bên bảo trì hay cung cấp hỗ trợ. Dự án không liên kết hoặc được VietMap, Google, Apple hay OpenAI bảo trợ.

> Phần mềm thử nghiệm dành cho nghiên cứu và kiểm thử khi xe đã đỗ an toàn; chưa được chứng nhận là thiết bị hỗ trợ lái xe. Dữ liệu có thể sai, thiếu hoặc trễ. Tuân thủ biển báo thực tế, điều kiện đường và pháp luật áp dụng. Đọc [thông báo trách nhiệm và quyền bên thứ ba](DISCLAIMER.vi.md) trước khi sử dụng; disclaimer không bảo đảm loại bỏ mọi rủi ro pháp lý.

## Ảnh xem trước CarPlay

Ảnh chụp từ CarPlay Simulator trên tuyến giả lập: bản đồ đầy đủ ở trạng thái 15/50 km/h và Dashboard ở trạng thái vượt giới hạn 74/50 km/h. Cả hai chỉ minh họa giao diện, không khẳng định độ chính xác trên đường thật.

| Bản đồ đầy đủ | Dashboard |
| --- | --- |
| ![Giao diện bản đồ đầy đủ GMapHUD trên CarPlay Simulator](docs/screenshots/gmaphud-full-map-f7c79e32.png) | ![Giao diện Dashboard GMapHUD trên CarPlay Simulator](docs/screenshots/gmaphud-dashboard.png) |

## Tính năng

- Bảng tốc độ trên bản đồ đầy đủ và thẻ dọc nhỏ gọn trong Dashboard; hỗ trợ màu bản đồ sáng/tối.
- Tốc độ hiện tại luôn có vị trí hiển thị, hiện `--` khi không có dữ liệu. Giới hạn chưa có dữ liệu được biểu diễn bằng biển nét đứt.
- Màu vàng từ mức thấp hơn giới hạn 5 km/h đến bằng giới hạn; màu đỏ khi vượt giới hạn. Chỉ có cảnh báo bằng hình ảnh, không có hệ thống cảnh báo âm thanh.
- Vị trí bảng theo vùng an toàn của thanh công cụ bản đồ. Nút hướng/la bàn của Google Maps CarPlay được ẩn.
- Tốc độ và giới hạn hết hiệu lực độc lập sau 5 giây. Tín hiệu duy trì kết nối không làm dữ liệu cũ trở nên mới.
- Có chế độ kiểm thử hiển thị khi đứng yên, kèm nhãn TEST và tự hết hạn.

Bản này chưa chuyển các biển cảnh báo khác, camera, khoảng cách cảnh báo, chỉ dẫn đường hoặc Live Activity. Không bao gồm giả lập GPS, phát lại vị trí, vượt DRM hay vượt kiểm tra thuê bao.

## Tương thích

| Thành phần | Cấu hình đã kiểm thử |
| --- | --- |
| Thiết bị / hệ điều hành | iPhone 11, iOS 18.6.2, jailbreak rootless |
| Google Maps | 26.39.0, UUID executable `E8BB60A0-E434-3412-AC6B-9B6800E031A6` |
| VietMap Live | 3.4.2 |
| Gói | `com.chou.googlemaps.vietmap` 0.1.10, arm64/arm64e |

Các kiểm tra chữ ký phương thức nội bộ và phiên bản/executable sẽ không kích hoạt phần tích hợp trên bản không được hỗ trợ. Chỉ trùng số phiên bản chưa bảo đảm executable của Google Maps khớp. Mã gói và định danh thông báo giữ nguyên để tương thích với bản đang cài.

Giao diện đã được kiểm tra bằng iPhone thật kết nối với CarPlay Simulator của Apple: bình thường, gần giới hạn, vượt giới hạn và Dashboard. Đã quan sát giá trị thật khi đứng yên và sự di chuyển bằng vị trí giả lập. Chưa xác lập độ chính xác trên đường thực tế, khả năng tương thích rộng với xe/đầu màn hình hay hoạt động nền ổn định qua các lần cập nhật ứng dụng/hệ điều hành. Giá trị VietMap được diễn giải theo km/h; khi phát tuyến giả lập, tốc độ ứng dụng ghi nhận có thể khác tốc độ phát đã chọn. Đây không phải thiết bị đo đã hiệu chuẩn.

## Cài đặt và gỡ bỏ

1. Dùng jailbreak rootless tương thích và ứng dụng được cài hợp lệ, có quyền sử dụng/thuê bao VietMap cần thiết. Dự án không cung cấp các thành phần này.
2. Sao chép **https://bechou0410.github.io/gmaphud/** vào **Sileo → Sources (Nguồn) → +** hoặc **Zebra → Sources → +**, làm mới rồi tìm **GMapHUD**. [Trang nguồn](https://bechou0410.github.io/gmaphud/) có nút thêm nhanh cho cả hai. Hoặc tải `.deb` tại [Releases](https://github.com/bechou0410/gmaphud/releases) và đối chiếu SHA-256 với `SHA256SUMS`.
3. Cài bằng trình quản lý gói của jailbreak. Kiểm tra thông báo gỡ các gói bridge/probe cũ được liệt kê trong [tweak/control](tweak/control). Gói này không gỡ TrueDash của nhà phát triển. Nguồn chỉ hỗ trợ gói rootless `iphoneos-arm64`.
4. Đóng và mở lại VietMap cùng Google Maps, rồi mở Google Maps trên CarPlay. Duy trì chế độ cảnh báo nền của VietMap. Chỉ có Live Activity chưa chứng minh dữ liệu tốc độ vẫn được cập nhật.

Không cung cấp hay yêu cầu mật khẩu SSH mặc định. Thường không cần respring nếu cả hai tiến trình ứng dụng đã được mở lại.

Để gỡ: gỡ `com.chou.googlemaps.vietmap` bằng trình quản lý gói, rồi đóng và mở lại cả hai ứng dụng. Xóa tệp không tự dỡ thư viện đã được nạp vào một tiến trình còn đang chạy.

## Build và kiểm thử

Cần macOS, công cụ dòng lệnh Xcode, Theos, toolchain hỗ trợ rootless và SDK iPhoneOS 16.5 được lấy theo giấy phép áp dụng. SDK và các phụ thuộc không được đóng kèm.

```sh
git clone https://github.com/bechou0410/gmaphud.git
cd gmaphud
sh test.sh
THEOS="$HOME/theos" sh build-tweak.sh
```

Gói được tạo trong `packages/`. Hai script dùng thư mục tạm và hỗ trợ đường dẫn checkout có dấu cách. Toolchain đã kiểm thử có cảnh báo linker tồn tại từ trước: `-multiply_defined is obsolete`.

## Duy trì nguồn Sileo

[Nguồn tĩnh](https://bechou0410.github.io/gmaphud/) được GitHub Pages xuất bản từ `main` → `/docs`. [build-repo.py](build-repo.py) đưa gói đã build vào nguồn, tạo chỉ mục và trang; [repo-template.html](repo-template.html) chứa bố cục dùng chung và [repo-locales.json](repo-locales.json) chứa nội dung tiếng Việt/Anh. Trang mặc định dùng tiếng Việt; [en.html](https://bechou0410.github.io/gmaphud/en.html) dùng tiếng Anh. Cấu hình xuất bản nằm trong Settings → Pages của repository. Xem log tại Actions hoặc bằng `gh api repos/bechou0410/gmaphud/pages/builds/latest`.

Để xuất bản gói đã rà soát, chạy `python3 build-repo.py packages/<package>.deb` với Python 3 và `dpkg-deb`, kiểm tra thay đổi trong `docs/`, rồi commit và push. Chỉ mục quảng bá phiên bản vừa cung cấp; tệp gói cũ vẫn giữ cho các lượt tải đã có. Tệp đã xuất bản là bất biến: tăng phiên bản trước khi đổi nội dung gói. Chỉ đưa gói GMapHUD sản xuất đã rà soát vào nguồn. Không đưa log, khóa, bản dump ứng dụng hoặc dữ liệu cục bộ khác vào `docs/`; toàn bộ thư mục này được công khai.

Đây là nguồn APT dạng phẳng qua HTTPS (`deb https://bechou0410.github.io/gmaphud/ ./`), có checksum gói/chỉ mục. Metadata Release chưa được ký PGP; riêng checksum không xác thực được người xuất bản. Dự án không cung cấp cách tắt cơ chế tin cậy/bảo mật APT toàn cục. Để hoàn tác một lần xuất bản nguồn, revert commit và push, đồng thời giữ tệp gói đã xuất bản. Xác nhận Pages build thành công và chỉ mục công khai khớp gói dự định trước khi thông báo cập nhật.

Nếu người dùng đã nâng cấp, khôi phục hành vi bằng một gói có phiên bản cao hơn. Chỉ hoàn tác chỉ mục nguồn không làm gói đã cài tự hạ phiên bản.

## Kiểm thử hiển thị khi đứng yên

Chạy trên iPhone trong shell có quyền dùng công cụ đã cài, khi Google Maps đang mở trên CarPlay:

```sh
/var/jb/usr/bin/gvm-test-speed 42 50 60
/var/jb/usr/bin/gvm-test-speed 48 50 60
/var/jb/usr/bin/gvm-test-speed 62 50 60
/var/jb/usr/bin/gvm-test-speed off
```

Tham số lần lượt là tốc độ hiện tại (0–400 km/h), giới hạn (1–400 km/h), thời lượng (1–300 giây). Chỉ mô hình hiển thị trên Google CarPlay thay đổi; GPS, dẫn đường và dữ liệu VietMap thật vẫn giữ nguyên. TEST hiển thị đến khi gọi `off` hoặc hết hạn. Sau kiểm thử, dữ liệu thật chưa có vẫn được hiển thị là chưa có.

## Kiến trúc và quyền riêng tư

`provider/vietmap-source.x` quan sát kênh Flutter overlay đang có của VietMap, chuyển tiếp handler/reply gốc không thay đổi. Tốc độ và giới hạn đã được kiểm tra, mỗi trường có thời điểm nhận theo đồng hồ đơn điệu riêng, được truyền qua trạng thái thông báo Darwin cục bộ. Hook Google chỉ áp dụng cho cửa sổ bản đồ CarPlay ngoài màn hình điện thoại; các view trên iPhone giữ lời gọi gốc.

Tweak không mở dịch vụ mạng, tải dữ liệu đo lường lên máy chủ, tạo daemon xuất bản hay lưu thông tin đăng nhập. `tmp/googlemaps-vietmap-source.log` và `tmp/googlemaps-vietmap.log` trong sandbox ứng dụng ghi giá trị/khả năng có dữ liệu tốc độ và giới hạn cùng trạng thái hook, không ghi tọa độ hay tuyến đường. Trạng thái thông báo cục bộ không được xác thực bằng mật mã và có thể bị phần mềm đặc quyền hoặc phần mềm được chèn khác tác động. Rà soát log trước khi chia sẻ.

## Giấy phép

Mã nguồn do dự án viết được cung cấp theo [MIT](LICENSE). Ứng dụng, bản đồ, dữ liệu giao thông/biển báo, nhãn hiệu, SDK và phụ thuộc của bên thứ ba vẫn chịu quyền và điều khoản của chủ sở hữu; dự án không phân phối hoặc cấp phép lại chúng. Xem [thông báo tiếng Việt](DISCLAIMER.vi.md) và [bản tiếng Anh](DISCLAIMER.md) về sử dụng hợp pháp, an toàn, tương thích và bảo hành. Giấy phép không chứng nhận tính hợp pháp, độ chính xác hay khả năng sử dụng trên đường.
