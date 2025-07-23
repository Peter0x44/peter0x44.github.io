@echo off
echo Starting Hugo development server...
echo Your blog will be available at: http://localhost:1313
echo Press Ctrl+C to stop the server
hugo server --bind=0.0.0.0 --port=1313
