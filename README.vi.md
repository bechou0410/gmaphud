# GMapHUD

**Tiếng Việt** · [English](README.md)

Tweak cho iOS jailbreak rootful/rootless, hiển thị **tốc độ hiện tại và giới hạn tốc độ từ VietMap Live, Waze hoặc GOFA trong Google Maps trên CarPlay và iPhone**. Ý tưởng từ tính năng bong bóng giao thông của DuoDash và TrueDash. Google Maps tiếp tục đảm nhiệm việc dẫn đường.

**Tác giả: chou · có AI hỗ trợ bằng Codex.** chou định hướng, kiểm thử và xuất bản dự án cộng đồng độc lập này; Codex hỗ trợ phát triển bằng AI. Ghi nhận này không có nghĩa OpenAI là đơn vị xuất bản, chủ sở hữu bản quyền, bên bảo trì hay cung cấp hỗ trợ. Dự án không liên kết hoặc được VietMap, Google, Apple hay OpenAI bảo trợ.

> Phần mềm thử nghiệm dành cho nghiên cứu và kiểm thử khi xe đã đỗ an toàn; chưa được chứng nhận là thiết bị hỗ trợ lái xe. Dữ liệu có thể sai, thiếu hoặc trễ. Tuân thủ biển báo thực tế, điều kiện đường và pháp luật áp dụng. Đọc [thông báo trách nhiệm và quyền bên thứ ba](DISCLAIMER.vi.md) trước khi sử dụng; disclaimer không bảo đảm loại bỏ mọi rủi ro pháp lý.

## Nguồn cảnh báo

Chọn **VietMap Live**, **Waze** hoặc **GOFA**; mỗi lần chỉ dùng một nguồn. Waze5.25.0; GOFA4.2.1 build3.

## Ảnh xem trước vị trí bong bóng

Đây là những ảnh CarPlay được dùng trong phần xem trước của Cài đặt. Ảnh minh họa đủ các vị trí hỗ trợ; số liệu và cảnh báo hiển thị chỉ là ví dụ, không khẳng định độ chính xác trên đường thực tế.

| Bản đồ đầy đủ · trên trái | Bản đồ đầy đủ · trên phải |
| --- | --- |
| ![Bong bóng trên trái trong bản đồ đầy đủ](docs/screenshots/full-map-top-left.png) | ![Bong bóng trên phải trong bản đồ đầy đủ](docs/screenshots/full-map-top-right.png) |

| Bản đồ đầy đủ · dưới trái | Bản đồ đầy đủ · dưới phải |
| --- | --- |
| ![Bong bóng dưới trái trong bản đồ đầy đủ](docs/screenshots/full-map-bottom-left.png) | ![Bong bóng dưới phải trong bản đồ đầy đủ](docs/screenshots/full-map-bottom-right.png) |

| Dashboard · bên trái | Dashboard · bên phải |
| --- | --- |
| ![Bong bóng bên trái trong Dashboard](docs/screenshots/dashboard-left.png) | ![Bong bóng bên phải trong Dashboard](docs/screenshots/dashboard-right.png) |

## Tính năng

Chọn kiểu bong bóng trong Cài đặt → GMapHUD → Giao diện. **Classic** (mặc định) giữ bong bóng quen thuộc. **New UI (beta)** gộp tốc độ và biển giới hạn vào một đồng hồ tròn: vòng tiến dần tới giới hạn, chuyển hổ phách khi sát và đỏ khi vượt; nhãn nguồn nằm dưới đồng hồ, biển cảnh báo hiện to với nhãn khoảng cách đầy dần khi xe tới gần. Hai kiểu dùng chung bộ biển báo vẽ phẳng theo hình và màu QCVN 41:2024; camera và CSGT là biển trắng có vòng đỏ như biển tốc độ kèm huy hiệu loại camera ở góc, các báo cáo khác chỉ có trong app là token tròn. Kích cỡ từ 50% đến 250%; ở New UI (beta), khi bố cục đã chọn không đủ chỗ cho cảnh báo ở cỡ lớn, cảnh báo xếp thành hàng dưới đồng hồ để đồng hồ giữ nguyên cỡ và vị trí. New UI (beta) còn hiện biển làn đường đúng như VietMap Live đang hiện, trong suốt thời gian VietMap hiện: mỗi làn một mũi tên, từ trái sang phải, dưới hoặc trên bong bóng ở bố cục ngang và cạnh đồng hồ ở bố cục dọc; như biển hiệu lực, biển làn không có khoảng cách. Khi Google Maps dẫn đường trên bản đồ đầy đủ của CarPlay, biển hiệu lực và làn chuyển xuống dưới ô chỉ dẫn của CarPlay, giữa ô đó và thời gian đến; bong bóng giữ đồng hồ và biển sắp tới, phần không vừa ở lại trong bong bóng. GMapHUDGuidanceRelay, nạp vào CarPlayTemplateUIHost, chỉ đọc vị trí CarPlay vẽ cột chỉ dẫn. Mở lại VietMap Live sau khi cài bản cập nhật để làn đường tới được Google Maps.

Bong bóng cho chọn bố cục ngang/dọc và kéo đổi thứ tự các module. Chỉnh kích cỡ và vị trí riêng cho Bản đồ đầy đủ, Dashboard và iPhone. Tối đa hai cảnh báo đường kèm khoảng cách; cảnh báo vượt tốc có thể hiển thị quanh bản đồ hoặc toàn màn hình CarPlay.

Trong Cài đặt iPhone → GMapHUD, chọn một trong bốn góc cho bản đồ đầy đủ và cạnh trái hoặc phải cho Dashboard. Ảnh phía trên minh họa từng lựa chọn. Mặc định cả hai ở phía trên bên phải. Chọn một nguồn VietMap Live, Waze hoặc GOFA. Vị trí mới áp dụng khi Google Maps CarPlay đang mở; phần relay trong SpringBoard khôi phục lựa chọn đã lưu sau khi giao diện máy nạp lại.

- Bảng tốc độ trên bản đồ đầy đủ và thẻ dọc nhỏ gọn trong Dashboard; hỗ trợ màu bản đồ sáng/tối.
- Tốc độ hiện tại luôn có vị trí hiển thị, hiện `--` khi không có dữ liệu. Giới hạn chưa có dữ liệu được biểu diễn bằng biển nét đứt.
- Màu vàng từ mức thấp hơn giới hạn 5 km/h đến bằng giới hạn; màu đỏ khi vượt giới hạn. Chỉ có cảnh báo bằng hình ảnh, không có hệ thống cảnh báo âm thanh.
- Vị trí bảng theo vùng an toàn của thanh công cụ bản đồ. Nút hướng/la bàn của Google Maps CarPlay được ẩn.
- Tốc độ và giới hạn hết hiệu lực độc lập sau 5 giây. Tín hiệu duy trì kết nối không làm dữ liệu cũ trở nên mới; Waze và GOFA chỉ xác nhận lại giới hạn hiện tại do chính ứng dụng đang giữ khi điện thoại đứng yên.
- Có chế độ kiểm thử hiển thị khi đứng yên, kèm nhãn TEST và tự hết hạn.


## Tương thích

| Thành phần | Cấu hình đã kiểm thử |
| --- | --- |
| Thiết bị / hệ điều hành | iPhone 11, iOS 18.6.2, jailbreak rootless |
| Google Maps | 26.40.3 |
| VietMap Live | 3.4.3 |
| Gói | `com.chou.googlemaps.vietmap` 0.2.5, arm64/arm64e |

Từ 0.1.13, Google Maps không còn bị giới hạn theo phiên bản hoặc UUID executable. Tweak vẫn kiểm tra các lớp và chữ ký phương thức cần thiết; vượt qua kiểm tra không bảo đảm mọi bản đều tương thích. Mã gói giữ nguyên. Từ 0.1.20, tweak dùng kênh thông báo dữ liệu thật có phiên bản mới; kênh thử hiển thị có thời hạn vẫn giữ tên cũ.

Từ 0.1.13, nguồn VietMap cũng không còn khóa phiên bản. Kiểm tra cấu trúc kênh Flutter và dữ liệu đầu vào vẫn được giữ lại. Các bản app mới vẫn cần kiểm chứng trên thiết bị.

Giao diện đã được kiểm tra bằng iPhone thật kết nối với CarPlay Simulator của Apple: bình thường, gần giới hạn, vượt giới hạn và Dashboard. Đã quan sát giá trị thật khi đứng yên và sự di chuyển bằng vị trí giả lập. Chưa xác lập độ chính xác trên đường thực tế, khả năng tương thích rộng với xe/đầu màn hình hay hoạt động nền ổn định qua các lần cập nhật ứng dụng/hệ điều hành. Giá trị VietMap được diễn giải theo km/h; khi phát tuyến giả lập, tốc độ ứng dụng ghi nhận có thể khác tốc độ phát đã chọn. Đây không phải thiết bị đo đã hiệu chuẩn.

## Cài đặt và gỡ bỏ

1. Dùng jailbreak tương thích và ứng dụng được cài hợp lệ, có quyền sử dụng/thuê bao VietMap cần thiết. Dự án không cung cấp các thành phần này.
2. Sao chép **https://gmaphud.caidat.app/** vào **Sileo → Sources (Nguồn) → +** hoặc **Zebra → Sources → +**, làm mới rồi tìm **GMapHUD**. [Trang nguồn](https://gmaphud.caidat.app/) có nút thêm nhanh cho cả hai. Hoặc tải `.deb` tại [Releases](https://github.com/bechou0410/gmaphud/releases) và đối chiếu SHA-256 với `SHA256SUMS`. [Nguồn GitHub Pages cũ](https://bechou0410.github.io/gmaphud/) vẫn hoạt động làm dự phòng; lượt tải trực tiếp qua nguồn này không được đếm.
3. Cài bằng trình quản lý gói của jailbreak. Kiểm tra thông báo gỡ các gói bridge/probe cũ được liệt kê trong [tweak/control](tweak/control). Gói này không gỡ TrueDash của nhà phát triển. Nguồn gồm gói rootless (`iphoneos-arm64`) và rootful (`iphoneos-arm`). Rootful cần kiểm thử trên iOS 14; các bản app cũ có thể cần sửa tích hợp thêm.
4. Đóng và mở lại VietMap cùng Google Maps, rồi mở Google Maps trên CarPlay. Duy trì chế độ cảnh báo nền của VietMap. Chỉ có Live Activity chưa chứng minh dữ liệu tốc độ vẫn được cập nhật.

Không cung cấp hay yêu cầu mật khẩu SSH mặc định. Sau khi cập nhật, respring một lần để nạp phần chạy nền, rồi mở lại Google Maps và Cài đặt. Tự đánh thức hỗ trợ quyền Khi dùng ứng dụng hoặc Luôn luôn; cần bật cảnh báo trong VietMap trước.

Để gỡ: gỡ `com.chou.googlemaps.vietmap` bằng trình quản lý gói, rồi đóng và mở lại cả hai ứng dụng. Xóa tệp không tự dỡ thư viện đã được nạp vào một tiến trình còn đang chạy.

## Build và kiểm thử

Cần macOS, Python 3.9+, công cụ dòng lệnh Xcode, Theos, toolchain hỗ trợ rootless và SDK iPhoneOS 16.5 được lấy theo giấy phép áp dụng. SDK và các phụ thuộc không được đóng kèm.

```sh
git clone https://github.com/bechou0410/gmaphud.git
cd gmaphud
sh test.sh
THEOS="$HOME/theos" sh build-tweak.sh all
```

Gói được tạo trong `packages/`. Hai script dùng thư mục tạm và hỗ trợ đường dẫn checkout có dấu cách. Toolchain đã kiểm thử có cảnh báo linker tồn tại từ trước: `-multiply_defined is obsolete`.

Các lệnh build/test giữ log đầy đủ tại máy và trả kết quả ngắn kèm nhãn lỗi cố định, luôn giữ mã thoát của lệnh. Không gọi AI hay API bên ngoài. Xem [hướng dẫn build/test](docs/build-triage.md) để đọc báo cáo và dùng tùy chọn `GMAPHUD_CHECK_RAW=1`.

## Duy trì nguồn Sileo

Quy tắc phiên bản: trong một chu kỳ phát triển chưa phát hành, mọi lần sửa, build và cài thử đều giữ cùng một phiên bản kế tiếp. Ví dụ bản đã phát hành là `0.1.13` thì tất cả bản thử dùng `0.1.14`; khi phát hành, push chính `0.1.14`. Chỉ sau lần phát hành đó, chu kỳ phát triển tiếp theo mới dùng `0.1.15`. Không tăng phiên bản theo từng lần thử. Có thể ghi mã commit hoặc checksum để phân biệt các bản build nội bộ cùng phiên bản; tuyệt đối không ghi đè gói đã công khai.

[Nguồn tĩnh](https://bechou0410.github.io/gmaphud/) được GitHub Pages xuất bản từ `main` → `/docs`. [build-repo.py](build-repo.py) đưa gói đã build vào nguồn, tạo chỉ mục, trang và depiction Sileo song ngữ có carousel ảnh CarPlay cùng tab nhật ký thay đổi; [repo-template.html](repo-template.html) chứa bố cục landing page dùng chung và [repo-locales.json](repo-locales.json) chứa nội dung tiếng Việt/Anh của trang. Trang mặc định dùng tiếng Việt; [en.html](https://gmaphud.caidat.app/en.html) dùng tiếng Anh. Cấu hình xuất bản nằm trong Settings → Pages của repository. Xem log tại Actions hoặc bằng `gh api repos/bechou0410/gmaphud/pages/builds/latest`.

[Nguồn cài đặt chính](https://gmaphud.caidat.app/) dùng proxy Cloudflare Pages để đếm lượt bắt đầu tải đầy đủ theo ngày, phiên bản và kiến trúc. Client đang dùng GitHub Pages vẫn hoạt động qua nguồn dự phòng. Xem [thống kê lượt tải](docs/download-statistics.md) để truy vấn số liệu, triển khai và rollback.

`docs/CydiaIcon*.png` là biểu tượng repo được Sileo tải từ gốc nguồn. Trường `Icon` trong [tweak/control](tweak/control) là biểu tượng riêng của gói; `docs/gmaphud-icon.svg/png` dùng cho favicon và trang web.

Để xuất bản gói đã rà soát, chạy `python3 build-repo.py packages/<rootless>.deb packages/<rootful>.deb` với Python 3 và `dpkg-deb`, kiểm tra thay đổi trong `docs/`, rồi commit và push. Chỉ mục quảng bá phiên bản vừa cung cấp; tệp gói cũ vẫn giữ cho các lượt tải đã có. Tệp đã xuất bản là bất biến: tăng phiên bản trước khi đổi nội dung gói. Chỉ đưa gói phát hành đã rà soát vào nguồn. YTHUD là gói rootless thử nghiệm riêng; thêm tệp .deb của YTHUD làm đối số thứ ba khi xuất bản gói này. Lần chạy chỉ có hai gói GMapHUD về sau sẽ giữ và xác minh gói YTHUD đã công bố. Không đưa log, khóa, bản dump ứng dụng hoặc dữ liệu cục bộ khác vào `docs/`; toàn bộ thư mục này được công khai.

Đây là nguồn APT dạng phẳng qua HTTPS (`deb https://gmaphud.caidat.app/ ./`), có checksum gói/chỉ mục. Metadata Release chưa được ký PGP; riêng checksum không xác thực được người xuất bản. Dự án không cung cấp cách tắt cơ chế tin cậy/bảo mật APT toàn cục. Để hoàn tác một lần xuất bản nguồn, revert commit và push, đồng thời giữ tệp gói đã xuất bản. Xác nhận Pages build thành công và chỉ mục công khai khớp gói dự định trước khi thông báo cập nhật.

Nếu người dùng đã nâng cấp, khôi phục hành vi bằng một gói có phiên bản cao hơn. Chỉ hoàn tác chỉ mục nguồn không làm gói đã cài tự hạ phiên bản.

## Kiểm thử hiển thị khi đứng yên

Chạy trên iPhone trong shell có quyền dùng công cụ đã cài, khi Google Maps đang mở trên CarPlay:

```sh
/var/jb/usr/bin/gvm-test-speed 42 50 60
/var/jb/usr/bin/gvm-test-speed 48 50 60
/var/jb/usr/bin/gvm-test-speed 62 50 60
/var/jb/usr/bin/gvm-test-speed 42 60 60 speed_limit_80:200 no_passing_in:400
/var/jb/usr/bin/gvm-test-speed 42 60 60 lanes=1,1,1,5,4@127
/var/jb/usr/bin/gvm-test-speed off
```

Tham số lần lượt là tốc độ hiện tại (0–400 km/h), giới hạn (1–400 km/h), thời lượng (1–300 giây); bản thử 0.1.14 có thể thêm tên hai biển VietMap và khoảng cách (0–10000 m) theo dạng `TÊN_BIỂN:MÉT`. Có thể nhập hai số trần để thử hai biển camera; `TÊN_BIỂN:-` hiện biển đang hiệu lực, không có khoảng cách. `lanes=MÃ@MÉT` thêm tối đa bảy làn thử theo mã làn của VietMap (1 đi thẳng, 4 rẽ phải, 5 thẳng hoặc phải, 16 quay đầu, 64 rẽ trái và tổng của chúng), từ trái sang phải; thêm `x` trước mã cho làn không được đi, bỏ `@MÉT` nếu không cần khoảng cách. Làn chỉ hiện ở New UI (beta). Chỉ mô hình hiển thị trên Google CarPlay thay đổi; GPS, dẫn đường và dữ liệu VietMap thật vẫn giữ nguyên. Mặc định TEST hiển thị đến khi gọi `off` hoặc hết hạn. Sau kiểm thử, dữ liệu thật chưa có vẫn được hiển thị là chưa có.

## Chẩn đoán lỗi

Sau khi cài, đóng và mở lại Google Maps và VietMap Live. Khi lỗi xuất hiện, vào **Cài đặt → GMapHUD → Chẩn đoán / Xuất log**, bấm **Làm mới**, rồi **Sao chép báo cáo** hoặc **Xuất file…** để chia sẻ file `.txt`. Báo cáo được hiển thị trước khi gửi; GMapHUD không tự gửi dữ liệu.

Bản tóm tắt chứa mẫu thiết bị (không có số sê-ri), iOS, trạng thái hook/kênh nguồn, độ mới dữ liệu và các mốc hiển thị CarPlay; giữ tối đa 16 mốc gần nhất mỗi app cùng mốc cuối từng bước. Bản tóm tắt không chứa tọa độ, tuyến đường hoặc tài khoản. Trạng thái có thể mất khi tiến trình/dịch vụ thông báo khởi động lại; hãy lấy báo cáo lúc tái hiện lỗi. Tự bổ sung phiên bản jailbreak và tên tweak chia màn hình.

Bản 0.1.21 còn đọc phiên bản và build Google Maps, VietMap Live đang cài, độc lập với việc module đã nạp hay chưa. Nếu không đọc được sẽ ghi rõ. Làm mới liệt kê tối đa ba crash `.ips`/`.crash` liên quan trong 7 ngày, mỗi file tối đa 2 MB; khi xuất có thể đính kèm file nguyên bản cùng bản tóm tắt. Tắt **Đính kèm crash liên quan** để chỉ xuất báo cáo. Crash có thể chứa thông tin thiết bị/app hoặc dữ liệu cá nhân; kiểm tra trước khi gửi. Không đọc được hoặc không tìm thấy crash sẽ được ghi rõ, không có nghĩa app chưa từng crash.

Bản 0.1.15 đã qua kiểm thử trên máy build, build arm64/arm64e và cài trên iPhone 11. Sao chép/chia sẻ và truyền chẩn đoán giữa app vẫn cần kiểm chứng thực tế; đây là bản bổ sung chẩn đoán, chưa phải bản sửa đã xác nhận cho lỗi thiếu dữ liệu trên iOS 16.

## Kiến trúc và quyền riêng tư

`provider/vietmap-source.x` quan sát kênh Flutter overlay đang có của VietMap, chuyển tiếp handler/reply gốc không thay đổi. Tốc độ và giới hạn đã được kiểm tra, mỗi trường có thời điểm nhận theo đồng hồ đơn điệu riêng, được truyền qua trạng thái thông báo Darwin cục bộ. Cảnh báo được đọc từ các chuỗi JSON trong `vml_main_channel/updateUpcommingAlerts` và `updateStickyAlerts`, đối chiếu mã băm chính xác với bộ ảnh 3.4.3 và chuyển qua bộ chuyển đổi VietMap thành tối đa hai cảnh báo có loại chung. Từ 0.1.20, tweak dùng [chuẩn đầu ra chung có phiên bản](docs/source-output-contract.md) cho tốc độ, giới hạn và cảnh báo trên cả hai giao diện Google Maps. Mỗi gói chỉ thuộc một nguồn đang chọn; gói chưa ghi xong hoặc thuộc lượt chọn cũ không được đọc. Hiện chỉ VietMap được kích hoạt. Danh sách rỗng sẽ xóa trạng thái nguồn; dữ liệu tự hết hạn sau 5 giây. Bản 0.1.14 đóng gói 46 ảnh biển VietMap để hiển thị; thông báo chỉ truyền dữ liệu số. Ảnh bên thứ ba không thuộc giấy phép MIT của dự án. Hook CarPlay áp dụng cho cửa sổ bản đồ ngoài màn hình điện thoại. Một lớp hiển thị riêng dùng cùng dữ liệu còn mới trong cửa sổ Google Maps trên iPhone, chỉ khi app ở phía trước và không chặn thao tác chạm.

Tweak không mở dịch vụ mạng, tải dữ liệu đo lường lên máy chủ, tạo daemon xuất bản hay lưu thông tin đăng nhập. `tmp/googlemaps-vietmap-source.log` và `tmp/googlemaps-vietmap.log` trong sandbox ứng dụng ghi giá trị/khả năng có dữ liệu tốc độ và giới hạn cùng trạng thái hook, không ghi tọa độ hay tuyến đường. Trạng thái thông báo cục bộ không được xác thực bằng mật mã và có thể bị phần mềm đặc quyền hoặc phần mềm được chèn khác tác động. Rà soát log trước khi chia sẻ.

## Giấy phép

Mã do dự án viết được cung cấp theo [MIT](LICENSE). Bộ ảnh hiển thị hiện tại do người dùng cung cấp; thay ảnh không xác nhận nguồn gốc hoặc cấp quyền phân phối lại. Ảnh không tự động thuộc giấy phép MIT của mã nguồn. Gói đã công khai trước đây có thể chứa ảnh VietMap nguyên bản. Ứng dụng, bản đồ, dữ liệu giao thông, nhãn hiệu, SDK và phụ thuộc của bên thứ ba vẫn thuộc quyền và điều khoản của chủ sở hữu. Xem [thông báo tiếng Việt](DISCLAIMER.vi.md) và [bản tiếng Anh](DISCLAIMER.md) về sử dụng hợp pháp, an toàn, tương thích và bảo hành. Giấy phép không chứng nhận tính hợp pháp, độ chính xác hay khả năng sử dụng trên đường.

Để chụp ảnh gốc cho Cài đặt, thêm `--photo` ở cuối lệnh để ẩn nhãn trong lượt mẫu có thời hạn đó. `gvm-test-speed position top-left left` đổi tạm vị trí Full Map/Dashboard, không ghi đè tùy chọn đã lưu; trả vị trí cũ sau khi chụp.

## Tự đánh thức VietMap Live

Sau khi cài, respring một lần để nạp phần chạy trong SpringBoard. Bật Dịch vụ định vị, cấp quyền **Khi dùng ứng dụng** hoặc **Luôn luôn** cho VietMap Live, rồi bật **Cài đặt → GMapHUD → Tự đánh thức VietMap Live**. Công tắc mặc định tắt, bị khóa khi chưa xác nhận đủ điều kiện và cập nhật khi đang xem trang. Nếu thu hồi quyền hoặc tắt Dịch vụ định vị, tính năng tự tắt; cấp lại quyền không tự bật lại.

Khi Google Maps đang hiện trên CarPlay hoặc iPhone, tweak có thể mở VietMap ở nền và giữ ứng dụng hoạt động mà không đưa lên màn hình iPhone. Cần bật cảnh báo trong VietMap trước; tweak không đăng nhập, kích hoạt thuê bao hay bảo đảm luôn có dữ liệu. Số lần mở lại được giới hạn để tránh vòng lặp. Khi rời Google Maps trên cả hai màn hình, phiên chạy nền bổ sung được gỡ sau khi tín hiệu hết hạn; quyền định vị gốc của VietMap được giữ nguyên. Nếu API hệ thống không tương thích, tính năng bị vô hiệu hóa. Đã thử đánh thức nền trên iPhone 11/iOS 18.6.2; phần khóa công tắc mới đã qua kiểm thử mã và build, chưa kiểm chứng đầy đủ chuyển quyền trên từng iOS. Rootful/iOS 14 còn cần kiểm thử thực tế. Bản này chưa tích hợp Waze.

Trạng thái nền ghi cục bộ tại `/var/mobile/Library/Logs/gmaphud-background.log`, giới hạn dung lượng và không ghi tọa độ. Google Maps có thể yêu cầu nguồn đang chạy gửi lại dữ liệu còn mới; dữ liệu cũ không được làm mới thời gian để tiếp tục hiển thị.

## Cảnh báo vượt tốc

Trong Cài đặt → GMapHUD → Cảnh báo vượt tốc, chọn Tắt, Bản đồ hoặc Toàn màn hình. Khi tốc độ vượt giới hạn hiện tại và dữ liệu còn mới, shadow đỏ nhấp nháy, mờ dần vào trong. Bản đồ chỉ cảnh báo trong vùng Google Maps; Toàn màn hình bao gồm sidebar và các ô Dashboard. Không áp dụng trên iPhone.

Nhịp cảnh báo tăng theo mức vượt: dưới 5 km/h — 0,75 Hz; từ 5 đến dưới 10 — 1,25 Hz; từ 10 trở lên — 2 Hz. Phạm vi bản đồ bám vùng nhìn thấy sau khi loại trừ sidebar và phần bị cắt ở các cạnh.

Độ đậm shadow được tách riêng: phạm vi bản đồ rõ hơn, toàn màn hình nhẹ hơn; nhịp nháy theo mức vượt tốc không thay đổi.


## Thiết lập bong bóng

Trong Cài đặt → GMapHUD, chọn Classic hoặc New UI (beta) ở mục Giao diện; thay đổi áp dụng cho mọi màn hình mà không cần mở lại Google Maps. Sau đó chọn Bản đồ đầy đủ, Dashboard hoặc Trên iPhone. Mỗi trang có công tắc riêng, vị trí, bố cục Ngang/Dọc/Tự động, kích cỡ và kéo thả thứ tự các phần. Hai preview ngang/dọc cập nhật khi đổi thứ tự. iPhone có thêm tinh chỉnh X/Y. Nút Đặt lại chỉ khôi phục phần tương ứng.

Trong **Chạy nền**, có thể bật tự đánh thức VietMap và tùy chọn thoát nguồn sau 20 giây ngắt CarPlay. Quyền định vị gốc được giữ nguyên.

## Gói khác trong nguồn

**[YTHUD](ythud/README.md)** — Gói rootless thử nghiệm đưa video YouTube vào ô nhạc Dashboard. Không khóa phiên bản YouTube, vẫn kiểm tra class/hàm nội bộ; đã kiểm YouTube 21.41.5 với bridge mở app trên CarPlay đang có. Livestream chưa hỗ trợ; còn lỗi đen hình không thường xuyên khi quay lại YouTube. [Depiction](https://bechou0410.github.io/gmaphud/ythud/).
