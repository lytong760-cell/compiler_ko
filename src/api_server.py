#!/usr/bin/env python3
"""
Module Store REST API Server for .ko Language
Implements the Firestore-compatible endpoints described in the .ko specification.

Endpoints:
  POST /v1/projects/{project}/databases/{db}/documents:runQuery  - List all libraries
  GET  /v1/projects/{project}/databases/{db}/documents/libraries/{lib}  - Get library metadata

Usage:
  python api_server.py [--port 8080] [--data-dir ./module_store_data]
"""

import json
import os
import sys
import argparse
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

PROJECT_ID = "argon-shine-w40ks"
DATABASE_ID = "ai-studio-ko-5b9b53f3-6da2-43ff-b76a-de7f7ee7b198"
API_KEY = os.environ.get("KO_FIRESTORE_API_KEY")
if not API_KEY:
    print("WARNING: KO_FIRESTORE_API_KEY environment variable is not set. The server will reject all requests.", file=sys.stderr)

BASE_PATH = f"/v1/projects/{PROJECT_ID}/databases/{DATABASE_ID}/documents"

class ModuleStore:
    def __init__(self, data_dir):
        self.data_dir = data_dir
        self.libraries_file = os.path.join(data_dir, "libraries.json")
        os.makedirs(data_dir, exist_ok=True)
        if not os.path.exists(self.libraries_file):
            self._save_libraries(self._default_libraries())

    def _default_libraries(self):
        return {
            "Random": {
                "name": f"projects/{PROJECT_ID}/databases/{DATABASE_ID}/documents/libraries/Random",
                "fields": {
                    "githubLink": {"stringValue": "https://github.com/ko-studio/ko-random"},
                    "description": {"stringValue": "Random number generation module for .ko"},
                    "version": {"stringValue": "1.0.0"},
                    "author": {"stringValue": "ko-studio"}
                }
            },
            "Os": {
                "name": f"projects/{PROJECT_ID}/databases/{DATABASE_ID}/documents/libraries/Os",
                "fields": {
                    "githubLink": {"stringValue": "https://github.com/ko-studio/ko-os"},
                    "description": {"stringValue": "Operating system interface module for .ko"},
                    "version": {"stringValue": "1.0.0"},
                    "author": {"stringValue": "ko-studio"}
                }
            },
            "Website": {
                "name": f"projects/{PROJECT_ID}/databases/{DATABASE_ID}/documents/libraries/Website",
                "fields": {
                    "githubLink": {"stringValue": "https://github.com/ko-studio/ko-website"},
                    "description": {"stringValue": "HTTP and web interaction module for .ko"},
                    "version": {"stringValue": "1.0.0"},
                    "author": {"stringValue": "ko-studio"}
                }
            },
            "Math": {
                "name": f"projects/{PROJECT_ID}/databases/{DATABASE_ID}/documents/libraries/Math",
                "fields": {
                    "githubLink": {"stringValue": "https://github.com/ko-studio/ko-math"},
                    "description": {"stringValue": "Advanced mathematics module for .ko"},
                    "version": {"stringValue": "1.0.0"},
                    "author": {"stringValue": "ko-studio"}
                }
            }
        }

    def _load_libraries(self):
        with open(self.libraries_file, "r") as f:
            return json.load(f)

    def _save_libraries(self, data):
        with open(self.libraries_file, "w") as f:
            json.dump(data, f, indent=2)

    def list_libraries(self):
        libs = self._load_libraries()
        documents = []
        for name, doc in libs.items():
            documents.append({
                "name": doc["name"],
                "fields": doc["fields"]
            })
        return documents

    def get_library(self, lib_name):
        libs = self._load_libraries()
        if lib_name not in libs:
            return None
        return libs[lib_name]

    def register_library(self, lib_name, github_url, description="", version="1.0.0", author="unknown"):
        libs = self._load_libraries()
        libs[lib_name] = {
            "name": f"projects/{PROJECT_ID}/databases/{DATABASE_ID}/documents/libraries/{lib_name}",
            "fields": {
                "githubLink": {"stringValue": github_url},
                "githubUrl": {"stringValue": github_url},
                "description": {"stringValue": description},
                "version": {"stringValue": version},
                "author": {"stringValue": author}
            }
        }
        self._save_libraries(libs)

class RequestHandler(BaseHTTPRequestHandler):
    store = None

    def log_message(self, format, *args):
        sys.stderr.write("%s - - [%s] %s\n" % (
            self.client_address[0],
            self.log_date_time_string(),
            format % args
        ))

    def _send_json(self, status, data):
        body = json.dumps(data).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _check_api_key(self):
        query = parse_qs(urlparse(self.path).query)
        key = query.get("key", [""])[0]
        return key == API_KEY

    def _parse_path(self):
        parsed = urlparse(self.path)
        path = parsed.path
        if path.startswith(BASE_PATH):
            return path[len(BASE_PATH):]
        return path

    def do_GET(self):
        if not self._check_api_key():
            self._send_json(403, {"error": {"message": "Invalid or missing API key", "status": "PERMISSION_DENIED"}})
            return

        rel_path = self._parse_path()

        if rel_path.startswith("/libraries/"):
            lib_name = rel_path[len("/libraries/"):]
            if not lib_name:
                self._send_json(400, {"error": {"message": "Library name required", "status": "INVALID_ARGUMENT"}})
                return

            doc = self.store.get_library(lib_name)
            if doc is None:
                self._send_json(404, {"error": {"message": f"Library '{lib_name}' not found", "status": "NOT_FOUND"}})
                return

            self._send_json(200, doc)
            return

        self._send_json(404, {"error": {"message": "Not found", "status": "NOT_FOUND"}})

    def do_POST(self):
        if not self._check_api_key():
            self._send_json(403, {"error": {"message": "Invalid or missing API key", "status": "PERMISSION_DENIED"}})
            return

        rel_path = self._parse_path()

        if rel_path == ":runQuery":
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8")
            try:
                request_data = json.loads(body)
            except json.JSONDecodeError:
                self._send_json(400, {"error": {"message": "Invalid JSON body", "status": "INVALID_ARGUMENT"}})
                return

            query = request_data.get("query", {})
            from_clause = query.get("from", [])
            collection_id = None
            if from_clause:
                collection_id = from_clause[0].get("collectionId")

            if collection_id == "libraries":
                documents = self.store.list_libraries()
                response = {
                    "document": documents,
                    "transaction": None,
                    "skippedResults": 0
                }
                self._send_json(200, response)
                return
            else:
                self._send_json(400, {"error": {"message": "Unsupported collection query", "status": "INVALID_ARGUMENT"}})
                return

        self._send_json(404, {"error": {"message": "Not found", "status": "NOT_FOUND"}})

    def do_PUT(self):
        if not self._check_api_key():
            self._send_json(403, {"error": {"message": "Invalid or missing API key", "status": "PERMISSION_DENIED"}})
            return

        rel_path = self._parse_path()

        if rel_path.startswith("/libraries/"):
            lib_name = rel_path[len("/libraries/"):]
            if not lib_name:
                self._send_json(400, {"error": {"message": "Library name required", "status": "INVALID_ARGUMENT"}})
                return

            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length).decode("utf-8")
            try:
                request_data = json.loads(body)
            except json.JSONDecodeError:
                self._send_json(400, {"error": {"message": "Invalid JSON body", "status": "INVALID_ARGUMENT"}})
                return

            fields = request_data.get("fields", {})
            github_url = ""
            if "githubLink" in fields:
                github_url = fields["githubLink"].get("stringValue", "")
            elif "githubUrl" in fields:
                github_url = fields["githubUrl"].get("stringValue", "")

            if not github_url:
                self._send_json(400, {"error": {"message": "githubLink or githubUrl field required", "status": "INVALID_ARGUMENT"}})
                return

            self.store.register_library(
                lib_name,
                github_url,
                fields.get("description", {}).get("stringValue", ""),
                fields.get("version", {}).get("stringValue", "1.0.0"),
                fields.get("author", {}).get("stringValue", "unknown")
            )

            doc = self.store.get_library(lib_name)
            self._send_json(200, doc)
            return

        self._send_json(404, {"error": {"message": "Not found", "status": "NOT_FOUND"}})

def main():
    parser = argparse.ArgumentParser(description=".ko Module Store API Server")
    parser.add_argument("--port", type=int, default=8080, help="Port to listen on")
    parser.add_argument("--data-dir", default="./module_store_data", help="Directory for library data")
    parser.add_argument("--host", default="0.0.0.0", help="Host to bind to")
    args = parser.parse_args()

    store = ModuleStore(args.data_dir)
    RequestHandler.store = store

    server = HTTPServer((args.host, args.port), RequestHandler)
    print(f".ko Module Store API Server running on http://{args.host}:{args.port}")
    print(f"Firestore-compatible base path: {BASE_PATH}")
    print(f"API Key: {API_KEY}")
    print("Press Ctrl+C to stop")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        server.shutdown()

if __name__ == "__main__":
    main()
