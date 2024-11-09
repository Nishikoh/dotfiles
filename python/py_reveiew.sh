pipx run radon cc . -a -nc
pipx run docformatter -r . -c
pipx run pyupgrade
pipx run cohesion -d ./ --verbose
pipx run interrogate -vv .
pipx run safety check --output json >insecure_report.json
pipx run safety review -f insecure_report.json --full-report
pipx run black --check --color .
pipx run flake8
pipx run autopep8 -r -d
pipx run isort --check .
pipx run flakeheaven lint
find . -name "*.py" | xargs pipx run darglint
pipx run pydocstyle
pipx run pycodestyle --show-pep8 .
pipx run bandit -r .
pipx run pylint .
pipx run prospector
pipx run pyflakes .
pipx run autoflake -c -r .
pipx run mccabe --min 5
pipx run yesqa
pipx run pip-audit
pipx run vulture .
pipx run detect-secrets scan --all-files
pipx run wily build ./
# pipx run wily diff ./ -r HEAD^1
pipx run pydeps ./ -T png
# pipx run pyan3 *.py --uses --no-defines --colored -v --annotated --html >| myuses.html
pipx run perflint .
pipx run refurb .
