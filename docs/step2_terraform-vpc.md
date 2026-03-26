---

# TerraformでVPC構築（Step2-2 / Step2-3）

目的：TerraformでAWSネットワークの基本構成を作り、Public/Privateの違いをルーティングで説明できる状態にする。

## 0. この資料で達成したいこと（ゴール）

- Step2-2：Public SubnetにEC2を置き、インターネット疎通・SSHができる
- Step2-3：Private Subnetを追加し、NATなしでも「なぜPrivateなのか」を説明できる

一言で言うと：Public/Privateは“Subnetの名前”じゃなく“ルート”で決まる。

---

## 1. 完成形の全体構成

前提（今回の例）

- VPC：10.0.0.0/16
- Public Subnet：10.0.1.0/24（ap-northeast-1a）
- Private Subnet：10.0.2.0/24（ap-northeast-1a）
- IGW：あり
- NAT：なし（課金回避で温存）

### 1-1. 構成図（概念）

Internet

↓

[Internet Gateway (IGW)]

↓

[Public Route Table] 0.0.0.0/0 → IGW

↓（関連付け）

[Public Subnet 10.0.1.0/24]

↓

[EC2 (Public IPあり / SSH可能)]

一方で Private はこうなる：

[VPC内通信はOK]

↓

[Private Route Table] 0.0.0.0/0 なし（NATもなし）

↓（関連付け）

[Private Subnet 10.0.2.0/24]

↓

[EC2を置いても外へ出られない（原則）]

一言で言うと：Publicは“外への出口（0.0.0.0/0）”がIGWに向いてる、Privateは出口が無い（または将来NAT）。

---

## 2. Step2-2：Public Subnet + EC2（作るものと意図）

### 2-1. 作成するリソース

- aws_vpc：ネットワークの器
- aws_internet_gateway：インターネットへの出入口
- aws_subnet.public：Public用のIP区画
- aws_route_table.public：Public Subnet用のルーティングテーブル
- aws_route.public_default：0.0.0.0/0 → IGW（これがPublicの本体）
- aws_route_table_association.public：Public SubnetにPublic RTを関連付け
- aws_security_group.ec2：SSHを自宅IPだけ許可
- aws_instance.public：Public Subnetに配置するEC2

### 2-2. 通信の流れ

A) SSH（自宅 → EC2）

- 自宅グローバルIP →（インターネット）→ IGW → Public Subnet上のEC2
- SGで my_ip_cidr のみ 22/tcp を許可するので安全

B) EC2のアウトバウンド（EC2 → インターネット）

- EC2 → Public RT（0.0.0.0/0）→ IGW → インターネット

一言で言うと：Step2-2は「0.0.0.0/0 → IGW を持つSubnetにEC2を置いた」だけ。

---

## 3. Step2-3：Private Subnet追加（作るものと意図）

### 3-1. 作成するリソース（追加分）

- aws_subnet.private：Private用のIP区画
- aws_route_table.private：Private用のルーティングテーブル
- aws_route_table_association.private：Private SubnetにPrivate RTを関連付け

重要：この段階では NATも作らないし、Private RTに 0.0.0.0/0 を作らない。

### 3-2. なぜ “NATなし” が成立するのか（設計意図）

- Privateにしたい＝インターネットに直接出さない
- だから Private RT には 0.0.0.0/0（デフォルトルート）を入れない
- すると、Private Subnet内のリソースは「VPC内宛て」以外の通信経路を持てない
- NAT Gatewayは課金が継続的に出るため、必要になるタイミングまで作らないと判断

### 3-3. map_public_ip_on_launch = false の意味

- そのSubnet上に起動したEC2に、デフォルトでPublic IPv4を付けない設定
- Private Subnetにこれを明示することで「うっかりPublic IPが付く事故」を防ぐ

一言で言うと：Privateは「出口（0.0.0.0/0）を持たない」＋「Public IPを自動で付けない」で守る。

---

## 4. Public/Privateの判定方法

Subnet名やタグでは判定しない。次の順で見る。

1) そのSubnetが関連付いているRoute Tableはどれ？

2) そのRoute Tableに 0.0.0.0/0 はある？

3) あったら、向き先は？

- IGWなら Public
- NATなら “Privateだがアウトバウンド可能”
- 無ければ “完全に外へ出ないPrivate”

4) SubnetがPublic IPを自動付与する設定か？（事故防止観点）

一言で言うと：Public/Privateはルートテーブルのデフォルトルートで決まる。

---

## 5. 検証項目（作った後にチェック）

### 5-1. Step2-2の確認

- EC2にSSHできる（my_ip_cidrが正しい）
- EC2から外に出られる（curl等）
- Public RTに 0.0.0.0/0 → IGW がある

### 5-2. Step2-3の確認

- Private Subnetが Private RTに関連付いている
- Private RTに 0.0.0.0/0 が無い
- Private Subnetは map_public_ip_on_launch = false

一言で言うと：確認は「関連付け」と「0.0.0.0/0の有無」だけ見れば良い。

---

## 6. よくあるミス

- ルートテーブルの関連付け漏れ（Subnetが意図と違うRTを使う）
- my_ip_cidr の指定ミスでSSHできない（/32忘れ、IP変動）
- “PrivateなのにPublic IPが付いてる” という混乱（Subnet側の設定を見てない）

一言で言うと：詰まりの8割はルートテーブル関連。

---
