import os
import re

pattern = re.compile(r'AKIA|BEGIN (RSA|OPENSSH) PRIVATE KEY|password\s*=\s*[\'"][^c]')
findings = []

for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in ['.git', 'node_modules', '.terraform']]
    for f in files:
        path = os.path.normpath(os.path.join(root, f))
        try:
            with open(path, 'r', encoding='utf-8', errors='ignore') as fp:
                for idx, line in enumerate(fp, 1):
                    if pattern.search(line):
                        findings.append((path, idx, line.strip()))
        except Exception:
            pass

print(f"Total secret scan findings: {len(findings)}")
for path, line_no, content in findings:
    print(f"{path}:{line_no}: {content}")
