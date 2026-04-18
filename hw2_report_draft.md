# 114-2 系統分析與設計 作業二
**姓名：陳冠宇**
**GitHub Repository：https://github.com/pierrechen2001/listen-ai**

---

## 第一部分：ListenAI 從過世到復活

---

### 任務 1：基本設置（16 分）

**1-2. Fork 後的 GitHub Repository 連結**

https://github.com/pierrechen2001/listen-ai

**3-6. 本地執行與截圖**

依照 README 指示，使用 `task up` 在本地啟動所有服務後，於瀏覽器開啟 `http://localhost:8501`，登入（admin / admin123）後可見以下畫面。

畫面中已將 `Hello! 梁安哲` 修改為 `Hello! 陳冠宇`（`frontend/app.py` 第 18 行）：

```python
# 修改前
st.text("Hello! 梁安哲")

# 修改後
st.text("Hello! 陳冠宇")
```

> **[截圖 1-1]** 瀏覽器顯示 ListenAI Dashboard，含 "Hello! 陳冠宇" 及關鍵字「機器人」搜尋結果 500 筆

---

### 任務 2：將 ListenAI 容器化（40 分）

#### 2.1 Frontend Dockerfile（Python / Streamlit）

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies first for better layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

EXPOSE 8501

CMD ["streamlit", "run", "app.py", "--server.port=8501", "--server.address=0.0.0.0"]
```

#### 2.2 Gateway Dockerfile（Node.js / Express）

```dockerfile
FROM node:20-slim

WORKDIR /app

# Install dependencies first for better layer caching
COPY package*.json ./
RUN npm ci --omit=dev

# Copy application code
COPY . .

EXPOSE 8000

CMD ["node", "src/index.js"]
```

#### 2.3 NLP Dockerfile（Python / FastAPI）

```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies first for better layer caching
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

EXPOSE 8001

CMD ["sh", "-c", "uvicorn app:app --host 0.0.0.0 --port ${NLP_PORT:-8001}"]
```

#### 2.4 Stat Dockerfile（Go / multi-stage build）

```dockerfile
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Download dependencies first for better layer caching
COPY go.mod go.sum ./
RUN go mod download

# Copy and build the application
COPY . .
RUN go build -o stat .

FROM alpine:latest

WORKDIR /app

COPY --from=builder /app/stat .

EXPOSE 8002

CMD ["./stat"]
```

#### 2.5–2.6 Docker Compose

```yaml
services:
  frontend:
    build:
      context: ./frontend
    ports:
      - "8501:8501"
    environment:
      - GATEWAY_URL=http://gateway:8000
    depends_on:
      - gateway
    restart: unless-stopped

  gateway:
    build:
      context: ./gateway
    ports:
      - "8000:8000"
    environment:
      - GATEWAY_PORT=8000
      - STAT_URL=http://stat:8002
      - NLP_URL=http://nlp:8001
      - JWT_SECRET=supersecret
      - DEMO_USER=admin
      - DEMO_PASS=admin123
    depends_on:
      - stat
      - nlp
    restart: unless-stopped

  nlp:
    build:
      context: ./nlp
    ports:
      - "8001:8001"
    restart: unless-stopped

  stat:
    build:
      context: ./stat
    ports:
      - "8002:8002"
    environment:
      - STAT_PORT=8002
      - SQLITE_PATH=/data/listenai.db
    volumes:
      - listenai_data:/data
    restart: unless-stopped

volumes:
  listenai_data:
```

#### 2.7 docker ps 截圖

執行指令：
```bash
docker ps --all --filter label=com.docker.compose.project
```

> **[截圖 2-7]**
```
CONTAINER ID   IMAGE                COMMAND                  CREATED         STATUS         PORTS                    NAMES
36b4ee4eb7c0   listen-ai-frontend   "streamlit run app.p…"   ...   Up   0.0.0.0:8501->8501/tcp   listen-ai-frontend-1
6e50250cd3b4   listen-ai-gateway    "docker-entrypoint.s…"   ...   Up   0.0.0.0:8000->8000/tcp   listen-ai-gateway-1
afa2f1f022b5   listen-ai-nlp        "sh -c 'uvicorn app:…"   ...   Up   0.0.0.0:8001->8001/tcp   listen-ai-nlp-1
18540530c33d   listen-ai-stat       "./stat"                 ...   Up   0.0.0.0:8002->8002/tcp   listen-ai-stat-1
```

---

### 任務 3：驗證容器化技術（32 分）

#### 3.1 各服務 Container Image 大小分析

執行 `docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | grep listen-ai`：

> **[截圖 3-1]**

| 服務 | 程式語言 | Base Image | Image 大小 |
|------|----------|-----------|-----------|
| listen-ai-frontend | Python | python:3.11-slim | **800 MB** |
| listen-ai-gateway | Node.js | node:20-slim | **329 MB** |
| listen-ai-nlp | Python | python:3.11-slim | **250 MB** |
| listen-ai-stat | Go | golang:1.23-alpine → alpine | **35 MB** |

**分析：**

差異最顯著的是 **stat（Go）**，僅 35 MB，其餘三者均在數百 MB 級別。原因如下：

1. **Go 靜態編譯 + Multi-stage build**：Go 可編譯成單一靜態執行檔，最終 image 僅需 alpine（約 7 MB）加上執行檔，無需任何 runtime。Go SDK 本身雖逾 600 MB，但透過 multi-stage build 完全不進入最終 image。
2. **Python runtime 較重**：即使使用 slim，Python 直譯器 + 套件（pandas、streamlit、altair 共約 700 MB 依賴）仍使最終 image 偏大。frontend 比 nlp 大的原因在於 streamlit 的依賴（如 pyarrow、numpy、pandas）遠多於 FastAPI。
3. **Node.js 居中**：node:20-slim 本身比 python:3.11-slim 輕，加上 gateway 的 npm 套件不多（5 個），故整體較小。

---

#### 3.2 Dockerfile 步驟順序對 Build 時間的影響

**實驗設計：**

以 frontend 為例，對應用程式碼做任意修改後，比較以下兩種 Dockerfile 的重 build 時間：

**正確順序（Correct Order）**
```dockerfile
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt   # ← 依賴層，code 不變時 cache HIT
COPY . .                                              # ← code 層，修改後 invalidate
```

**調換順序（Swapped Order）**
```dockerfile
COPY . .                                              # ← code 層，修改後 invalidate
RUN pip install --no-cache-dir -r requirements.txt   # ← 依賴層，前層失效故強制重跑
```

**實驗結果：**

> **[截圖 3-2]** 兩次 build 的 terminal 輸出

| 情況 | Build 時間 |
|------|-----------|
| 初次 build（無 cache 基準） | ~210 s |
| **正確順序**，修改程式碼後重 build | **4 s** |
| **調換順序**，修改程式碼後重 build | **227 s** |

**原因分析：**

Docker 採用 **layer-by-layer caching** 策略：某一層的內容發生改變後，其後所有層的 cache 均告失效。

- **正確順序**：`requirements.txt` 未改動，`pip install` 層的 cache 命中，只需重新執行最後的 `COPY . .`，故僅需 4 秒。
- **調換順序**：`COPY . .`（含修改後的程式碼）放在第一步，任何程式碼改動都使此層失效，導致 `pip install` 被迫重新執行（約 210 秒），效果與無 cache 完全相同。

結論：**依賴安裝應永遠在複製應用程式碼之前執行**，此為 Dockerfile 最佳實踐之一。

---

#### 3.3 python vs python-slim Base Image 比較

**實驗方法：** 分別以 `python:3.11` 與 `python:3.11-slim` 為 base image 進行無 cache 的完整 build。

> **[截圖 3-3]** 兩個 image 的大小與 build 時間比較

| Base Image | Build 時間（無 cache） | Image 大小 |
|-----------|----------------------|-----------|
| `python:3.11`（full） | ~230 s | **~1.7 GB** |
| `python:3.11-slim` | ~230 s | **~800 MB** |

**原因分析：**

Build 時間相近，因為兩者都需下載並安裝相同的 Python 套件（streamlit、pandas 等）。差異主要體現在 **Image 大小**：

- `python:3.11`（full）基於 Debian，預裝完整的系統工具鏈（gcc、make、build-essential、curl、git 等），基礎 image 約 1.0 GB；加上應用依賴後達 ~1.7 GB。
- `python:3.11-slim` 僅保留 Python 執行環境所需的最小系統套件，基礎 image 約 95 MB；加上應用依賴後約 800 MB，**節省約 53% 空間**。

由於 ListenAI 的 Python 服務（frontend / nlp）不需編譯 C extension，也不需要系統工具，`python:3.11-slim` 完全足夠，且在 CI/CD 推送與 cloud 部署時能顯著節省頻寬與儲存成本，應優先採用。

---

#### 3.4 SQLite Volume 持久化

**問題說明：** 若 SQLite 資料庫直接包含於 Container Image 中，每次容器重建都會遺失使用者新增的資料。

**解決方案：** 在 `docker-compose.yml` 中加入 named volume，stat 服務透過 `SQLITE_PATH=/data/listenai.db` 指向 volume 路徑：

```yaml
stat:
  environment:
    - SQLITE_PATH=/data/listenai.db
  volumes:
    - listenai_data:/data      # ← 掛載 named volume

volumes:
  listenai_data:               # ← 定義 named volume
```

**操作步驟：**

```bash
# (a) 啟動系統
docker compose up -d

# (b) 確認「我好喜歡資管系」無搜尋結果

# (c) 在 Add Post 頁面新增「我好喜歡資管系」

# (d) 停止所有 containers
docker compose stop

# (e) 刪除所有 containers
docker compose rm -f

# (f) 重新啟動（volume 資料保留）
docker compose up -d

# (g) 確認「我好喜歡資管系」有搜尋結果
```

> **操作影片 YouTube 連結：** [待錄製後填入]

---

## 第二部分：把書評變成現金流——ListenAI 的決策升級

---

### 任務 1：分析 BPMN 流程圖（12 分）

> **[插入 BPMN 圖片]**（原始檔：`bpmn_diagram.drawio`，可用 draw.io / diagrams.net 開啟）

**五條泳道說明：**

| 泳道 | 角色 | 主要職責 |
|------|------|---------|
| 使用者 | 書籍讀者 | 閱讀書籍後撰寫並發布書評 |
| 四葉草書評 | 社群書評平台 | 收錄書評、觸發 ListenAI 分析流程 |
| 四葉草書店資料分析師 | 分析決策者 | 審視 Dashboard 報告、判斷可信度、提出備貨建議 |
| 四葉草書店零售人員 | 執行採購 | 依建議判斷庫存、完成上架或向出版社下單 |
| 出版社 | 外部供應商 | 接收訂單、備貨後出貨給書店 |

**流程說明：**

**主要流程：**
1. **書評發布**：使用者於四葉草書評平台發布書評
2. **資料擷取**：ListenAI 自動爬取書評，存入資料庫（Stat 模組）
3. **情感分析**：NLP 模組對書評執行正/中/負情感分類
4. **詞頻統計**：Stat 模組計算關鍵字頻率與每日趨勢
5. **報告呈現**：系統自動產生 Dashboard 報告
6. **人工審核**：資料分析師登入 Dashboard 檢視結果，判斷分析是否可信
7. **備貨建議**：分析師確認後，提交備貨建議給零售人員
8. **庫存判斷**：零售人員檢查庫存
   - 庫存充足 → 直接上架熱門書籍
   - 庫存不足 → 向出版社下訂單
9. **出版社出貨**：出版社備貨後出貨，書店完成上架

**例外處理流程（資料探勘結果誤判）：**

若分析師判斷結果不可信（例如諷刺語氣被誤判為正面情感），觸發**人工重新標註**機制：
- 分析師手動標記誤判樣本
- 修正後的樣本回送 NLP 模組重新分析
- 重新產生報告後再次審核
- 確認無誤後繼續後續流程

此例外處理確保誤判不會直接影響備貨決策，避免如「多進 200 本賣不出去」的商業損失。

---

*程式碼已上傳至：https://github.com/pierrechen2001/listen-ai*
