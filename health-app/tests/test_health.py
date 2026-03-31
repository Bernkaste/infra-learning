import app

def test_health_returns_ok():
    client = app.app.test_client()
    resp = client.get("/health")
assert resp.status_code == 200
assert resp.data == b"ok"