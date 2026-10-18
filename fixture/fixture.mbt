///|
let users_json : String =
  #|[
  #|  {"id": 1, "name": "Alice", "age": 34, "role": "admin", "active": true, "tags": ["ops", "oncall"], "address": {"city": "Tokyo", "zip": "100-0001"}, "joined": "2021-04-01"},
  #|  {"id": 2, "name": "Bob", "age": 27, "role": "dev", "active": true, "tags": ["backend"], "address": {"city": "Osaka", "zip": "530-0001"}, "joined": "2022-07-15"},
  #|  {"id": 3, "name": "佐藤 花子", "age": 41, "role": "dev", "active": true, "tags": ["frontend", "a11y"], "address": {"city": "Tokyo", "zip": "150-0002"}, "joined": "2019-11-20"},
  #|  {"id": 4, "name": "Carol", "age": 30, "role": "design", "active": true, "tags": [], "address": {"city": "Fukuoka", "zip": "810-0001"}, "joined": "2023-01-10"},
  #|  {"id": 5, "name": "Dave", "age": 23, "role": "dev", "active": false, "tags": ["intern"], "address": {"city": "Sapporo", "zip": "060-0001"}, "joined": "2024-06-01"},
  #|  {"id": 6, "name": "Eve", "age": 38, "role": "security", "active": true, "tags": ["oncall", "audit"], "address": {"city": "Tokyo", "zip": "106-0032"}, "joined": "2020-03-03"},
  #|  {"id": 7, "name": "鈴木 一郎", "age": 29, "role": "ops", "active": true, "tags": ["ops"], "address": {"city": "Nagoya", "zip": "450-0002"}, "joined": "2022-02-28"},
  #|  {"id": 8, "name": "Frank", "age": 52, "role": "admin", "active": false, "tags": ["legacy"], "address": {"city": "Osaka", "zip": "542-0076"}, "joined": "2015-09-09"}
  #|]
  #|

///|
pub let orders_csv : String =
  #|order_id,user_id,item,qty,price,date
  #|1001,1,Keyboard,1,12800,2026-09-01
  #|1002,2,Mouse,2,3200,2026-09-02
  #|1003,3,Monitor,1,45800,2026-09-02
  #|1004,1,USB-C cable,3,1200,2026-09-05
  #|1005,6,"Desk, standing",1,59800,2026-09-07
  #|1006,4,Pen tablet,1,38000,2026-09-10
  #|1007,7,Mouse,1,3200,2026-09-11
  #|1008,2,Monitor,2,45800,2026-09-15
  #|1009,8,Keyboard,1,12800,2026-09-20
  #|1010,3,Headphones,1,24800,2026-09-28
  #|

///|
let config_json : String =
  #|{
  #|  "name": "patchbay",
  #|  "version": "0.1.0",
  #|  "server": {"host": "localhost", "port": 8080, "tls": false},
  #|  "features": {"history": true, "export": ["json", "md", "tsv"], "max_rows": 500},
  #|  "owners": [
  #|    {"name": "Alice", "email": "alice@example.com"},
  #|    {"name": "Eve", "email": "eve@example.com"}
  #|  ]
  #|}
  #|

///|
pub let server_log : String =
  #|2026-10-16 09:00:01 INFO  server started on :8080
  #|2026-10-16 09:00:05 INFO  connected to database
  #|2026-10-16 09:12:44 WARN  slow query took 1532ms
  #|2026-10-16 09:30:10 ERROR failed to send mail: timeout
  #|2026-10-16 10:02:00 INFO  user 3 logged in
  #|2026-10-16 10:15:27 ERROR disk usage above 90%
  #|2026-10-16 11:00:00 INFO  nightly job scheduled
  #|

///|
pub let users : Json = @json.parse(users_json) catch { _ => panic() }

///|
pub let config : Json = @json.parse(config_json) catch { _ => panic() }
