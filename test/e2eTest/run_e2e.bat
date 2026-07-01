@echo off
echo.
echo ========================================================
echo 1. Running E2E Tests
echo ========================================================
echo Running pytest and saving output to e2e_test_results.txt...
python -m pytest "%~dp0test_shortener_e2e.py" > "%~dp0e2e_test_results.txt" 2>&1

echo.
echo ========================================================
echo 2. Saving the results
echo ========================================================
echo Tests finished! Results have been saved to e2e_test_results.txt
echo Outputting results to console:
echo.
type "%~dp0e2e_test_results.txt"
