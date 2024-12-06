import os
import sys
import json
import mimetypes

def get_mime_type(file_path):
    mime_type, _ = mimetypes.guess_type(file_path)
    return mime_type or "application/octet-stream"

if __name__ == "__main__":
    file_path = sys.argv[1]
    mime_type = get_mime_type(file_path)
    print(json.dumps({"mime_type": mime_type}))