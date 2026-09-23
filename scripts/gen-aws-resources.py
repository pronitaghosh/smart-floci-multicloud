#!/usr/bin/env python3
"""Generate docs/aws-resources.svg -- the resource inventory diagram.

One panel per Terragrunt stack, one row per resource type with its count. The
left edge of each row carries the fidelity colour, which is the only thing in
the diagram that is not simply an inventory fact.

    python3 scripts/gen-aws-resources.py docs/aws-resources.svg

To rasterise (headless Chrome, wrapped in a zero-margin page so the screenshot
is exactly the viewBox -- take the width/height from the <svg> tag):

    printf '<!doctype html><style>html,body{margin:0}svg{display:block}</style>' \\
      > /tmp/d.html && cat docs/aws-resources.svg >> /tmp/d.html
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \\
      --headless --disable-gpu --hide-scrollbars \\
      --force-device-scale-factor=1.5 --window-size=3200,<height> \\
      --screenshot=docs/aws-resources.png file:///tmp/d.html

Counts are maintained here by hand and must match the table in
docs/aws-resources.md. They are cross-checked against the per-stack subtitles
and the header total below, so a typo fails loudly rather than shipping.

Text is wrapped by hand -- one list entry per rendered line. There is no
measurement pass, so a line that is too long will simply overflow its box;
the per-column budgets are noted against each panel.
"""
import html
import sys

W = 3200

# ---------------------------------------------------------------- palette
INK   = "#0f172a"
BODY  = "#334155"
MUTED = "#64748b"
LINE  = "#e2e8f0"
WHITE = "#ffffff"

STACKS = {
    "BOOTSTRAP": dict(accent="#059669", deep="#047857", fill="#f0fdf9", chip="#10b981"),
    "IAM":       dict(accent="#d97706", deep="#b45309", fill="#fffbeb", chip="#f59e0b"),
    "STATEFUL":  dict(accent="#e11d48", deep="#be123c", fill="#fff1f3", chip="#f43f5e"),
    "STANDARD":  dict(accent="#2563eb", deep="#1d4ed8", fill="#eff6ff", chip="#3b82f6"),
}

# Fidelity, matching the legend and the behaviour summary at the foot.
FID = {
    "faithful": "#14b8a6",   # a real container backs it
    "partial":  "#f59e0b",   # in-process, works, deviations noted
    "broken":   "#ef4444",   # no data plane
    "tooling":  "#a855f7",   # platform tooling via Helm, not AWS
}

# ---------------------------------------------------------------- content
# Block kinds:
#   ("sec",   title, subtitle|None, [(name, count, fidelity)...], [note lines])
#   ("out",   title, [lines])          values handed to a later stack
#   ("note",  title, [lines])          a plain callout
#   ("warn",  title, [lines])          a callout in the stack's accent colour
#   ("split", [(title, [lines]), (title, [lines])])
#
# Line budgets, in characters, at the note font size:
#   BOOTSTRAP 62 · IAM 48 · STATEFUL 60 · STANDARD 108 (split halves: 50)

CONTENT = {
    "BOOTSTRAP": ("34 resources", "nothing exists without it", [
        ("sec", "VPC & NETWORKING", "metadata only — no packet traverses it", [
            ("aws_vpc", 1, "partial"),
            ("aws_subnet", 4, "partial"),
            ("aws_internet_gateway", 1, "partial"),
            ("aws_route_table", 2, "partial"),
            ("aws_route_table_association", 4, "partial"),
            ("aws_security_group", 3, "partial"),
        ], [
            "subnets: public-1a · public-1b · private-1a · private-1b",
            "security groups: shared · alb · redis",
            "EKS role tags are applied per subnet type. Rules are created",
            "and readable; floci does not enforce them.",
            "Real connectivity is Docker networking.",
        ]),
        ("sec", "ENCRYPTION", "in-process, but a genuine round-trip", [
            ("aws_kms_key", 1, "faithful"),
            ("aws_kms_alias", 1, "faithful"),
        ], [
            "encrypt/decrypt verified from the host and from inside a pod",
        ]),
        ("sec", "CONTAINER REGISTRY", "real registry:2 container", [
            ("aws_ecr_repository", 5, "faithful"),
        ], [
            "k3s pulls from it over plain HTTP — the daemon needs it",
            "listed in insecure-registries",
        ]),
        ("sec", "OBJECT STORAGE", None, [
            ("aws_s3_bucket", 1, "faithful"),
            ("aws_s3_bucket_versioning", 1, "faithful"),
            ("aws_s3_bucket_server_side_encryption_configuration", 1, "partial"),
            ("aws_s3_bucket_public_access_block", 1, "faithful"),
            ("aws_s3_bucket_policy", 1, "faithful"),
        ], [
            "SSE-KMS accepted but not reported back on head-object",
        ]),
        ("sec", "CERTIFICATES", None, [
            ("aws_acm_certificate", 1, "partial"),
        ], [
            "reports ISSUED without validation ever happening",
        ]),
        ("sec", "PARAMETER STORE", None, [
            ("aws_ssm_parameter", 6, "faithful"),
        ], [
            "/smartcloud/environment · /smartcloud/ecr/<service> ×5",
        ]),
        ("out", "CARRIED FORWARD VIA resolved:", [
            "vpc_id · all_subnet_ids · public_subnet_ids",
            "private_subnet_ids · security_group_ids · kms_key_arn",
        ]),
    ]),

    "IAM": ("8 resources", "roles and policies only", [
        ("sec", "IDENTITY & ACCESS", None, [
            ("aws_iam_role", 3, "partial"),
            ("aws_iam_role_policy", 1, "partial"),
            ("aws_iam_role_policy_attachment", 4, "partial"),
        ], [
            "cluster-role · node-role · app-role",
        ]),
        ("out", "CARRIED FORWARD VIA resolved:", [
            "role_arns",
        ]),
        ("warn", "NOT ENFORCED", [
            "Roles, policies and attachments are all created",
            "and readable. Nothing evaluates them: every",
            "call in this project uses test/test credentials",
            "and succeeds regardless of policy.",
            "",
            "An over-permissive policy and a correct one are",
            "indistinguishable here. IAM is a modelling",
            "exercise, not an authorization one.",
        ]),
    ]),

    "STATEFUL": ("11 resources", "data-bearing", [
        ("sec", "RDS", "real postgres:16 container", [
            ("aws_db_instance", 1, "partial"),
            ("aws_db_subnet_group", 1, "partial"),
        ], [
            "real SQL, real persistence",
            "storage_encrypted and kms_key_id are accepted and read",
            "back unset, so every plan wants to replace the database",
        ]),
        ("sec", "ELASTICACHE", "no container behind it", [
            ("aws_elasticache_replication_group", 1, "broken"),
        ], [
            "reports available; the endpoint is the string “localhost”",
            "unreachable from a pod — caching is disabled in the demo",
        ]),
        ("sec", "SECRETS MANAGER", None, [
            ("aws_secretsmanager_secret", 4, "faithful"),
            ("aws_secretsmanager_secret_version", 2, "faithful"),
        ], [
            "app-credentials · argocd-admin · vault root token",
            "and recovery keys",
        ]),
        ("sec", "ENCRYPTION", "vault prerequisites, the AWS half", [
            ("aws_kms_key", 1, "faithful"),
            ("aws_kms_alias", 1, "faithful"),
        ], [
            "auto-unseal key — Vault calls Encrypt/Decrypt on it at",
            "every seal and unseal",
        ]),
        ("out", "CARRIED FORWARD VIA resolved:", [
            "vault_unseal_key_ids",
            "vault_root_token_secrets",
            "vault_recovery_key_secrets",
        ]),
    ]),

    "STANDARD": ("14 resources", "everything needing the layers below", [
        ("sec", "EKS", "real rancher/k3s container", [
            ("aws_eks_cluster", 1, "faithful"),
            ("aws_eks_node_group", 1, "partial"),
        ], [
            "a genuine Kubernetes API — aws eks get-token works against it, because floci wires a "
            "token-auth webhook into the apiserver",
            "the node group is metadata only: the node IS the k3s container, so desired_size does "
            "nothing and there is no autoscaling",
        ]),
        ("sec", "PLATFORM TOOLING", "workloads managed by Terraform", [
            ("helm_release", 3, "tooling"),
            ("kubernetes_namespace", 2, "tooling"),
            ("null_resource", 2, "tooling"),
        ], [
            "vault · argocd · argocd-apps",
        ]),
        ("split", [
            ("Vault", [
                "3× Raft, auto-unsealed by KMS",
                "root token → Secrets Manager",
                "never enters terraform state",
                "Sealed: false",
            ]),
            ("ArgoCD", [
                "reconciles k8s/ from git",
                "owns the 4 Deployments",
                "real committed image refs",
                "Synced / Healthy",
            ]),
        ]),
        ("note", "APPLICATION", [
            "gateway :4000  ·  user-service :4001  ·  order-service :4002  ·  payment-service :4003",
            "2 replicas each · real traffic · real SQL · service-to-service HTTP",
            "pod network 10.42.0.0/16 — the ALB has no route here",
        ]),
        ("sec", "LOAD BALANCING", "HTTP proxy inside the floci container", [
            ("aws_lb", 1, "partial"),
            ("aws_lb_target_group", 1, "partial"),
            ("aws_lb_listener", 2, "partial"),
        ], [
            "really proxies HTTP to registered targets, health checks included",
            "target_type = ip is correct for real EKS, but floci cannot reach pods — the demo "
            "registers a NodePort instead",
        ]),
        ("sec", "PARAMETER STORE", None, [
            ("aws_ssm_parameter", 1, "faithful"),
        ], [
            "/smartcloud/gateway_url",
        ]),
        ("warn", "aws_cloudfront_* — DEFINED BUT DISABLED LOCALLY", [
            "aws_cloudfront_distribution · aws_cloudfront_origin_access_control",
            "",
            "The AWS provider segfaults reading floci's response. GetDistribution omits",
            "OriginGroups; provider v6.61.0 dereferences it unguarded (distribution.go:1150)",
            "and takes unrelated in-flight resources down with it, orphaning them from state.",
        ]),
    ]),
}

# Every count appears three times -- on a row, in the panel's own subtitle and
# in the header badge. Disagreement between them is the easiest way for this
# diagram to start lying, so fail here rather than render a wrong number.
TOTAL = 67
_totals = {}
for _name, (_label, _sub, _blocks) in CONTENT.items():
    _n = sum(c for b in _blocks if b[0] == "sec" for _, c, _ in b[3])
    _declared = int(_label.split()[0])
    assert _n == _declared, f"{_name}: rows total {_n}, subtitle says {_declared}"
    _totals[_name] = _n
assert sum(_totals.values()) == TOTAL, \
    f"stacks total {sum(_totals.values())}, header badge says {TOTAL}"

# The resolved: flow is three independent edges, not one chain: bootstrap feeds
# stateful, iam feeds standard, stateful feeds standard.
FLOW = [
    ("BOOTSTRAP", "STATEFUL",
     ["vpc_id · subnet_ids", "security_group_ids · kms_key_arns"]),
    ("IAM", "STANDARD", ["role_arns"]),
    ("STATEFUL", "STANDARD",
     ["vault_unseal_key_ids", "vault_root_token_secrets"]),
]

LEGEND = [
    ("faithful", "real container behind it — high fidelity"),
    ("partial",  "in-process emulation — works, deviations noted"),
    ("broken",   "no data plane — unusable or misleading"),
    ("tooling",  "platform tooling via Helm, not AWS"),
]

# ---------------------------------------------------------------- geometry
COLS = [
    ("BOOTSTRAP", 48, 720),
    ("IAM", 792, 560),
    ("STATEFUL", 1368, 656),
    ("STANDARD", 2040, 1112),
]
PANEL_Y     = 246
PANEL_PAD   = 22
PANEL_HEAD  = 92
ROW_H       = 52
ROW_GAP     = 9
SEC_TITLE_H = 40
SEC_SUB_H   = 26
SEC_PAD     = 14
SEC_GAP     = 20
NOTE_LH     = 25
BOX_TITLE_H = 34

out = []
def add(s): out.append(s)
def esc(s): return html.escape(str(s), quote=False)

def text(x, y, s, size=20, fill=INK, weight="400", anchor="start"):
    add(f'<text x="{x:.0f}" y="{y:.0f}" font-size="{size}" font-weight="{weight}" '
        f'fill="{fill}" text-anchor="{anchor}">{esc(s)}</text>')

def rrect(x, y, w, h, r, fill, stroke=None, sw=1.5):
    s = f' stroke="{stroke}" stroke-width="{sw}"' if stroke else ""
    add(f'<rect x="{x:.0f}" y="{y:.0f}" width="{w:.0f}" height="{h:.0f}" rx="{r}" '
        f'fill="{fill}"{s}/>')

def block_height(b):
    kind = b[0]
    if kind == "sec":
        _, _, sub, rows, notes = b
        h = SEC_TITLE_H + (SEC_SUB_H if sub else 0) + SEC_PAD
        h += len(rows) * ROW_H + (len(rows) - 1) * ROW_GAP
        if notes:
            h += 12 + len(notes) * NOTE_LH
        return h + SEC_PAD
    if kind in ("out", "note", "warn"):
        lines = b[2]
        return BOX_TITLE_H + SEC_PAD + len(lines) * NOTE_LH + SEC_PAD
    if kind == "split":
        halves = b[1]
        return BOX_TITLE_H + SEC_PAD + max(len(l) for _, l in halves) * NOTE_LH + SEC_PAD
    raise ValueError(kind)

def panel_height(name):
    _, _, blocks = CONTENT[name]
    h = PANEL_HEAD + PANEL_PAD * 2
    for i, b in enumerate(blocks):
        h += block_height(b) + (SEC_GAP if i else 0)
    return h

PANEL_H = max(panel_height(n) for n, _, _ in COLS)
FLOW_Y  = PANEL_Y + PANEL_H + 34
FLOW_H  = 152
LEG_Y   = FLOW_Y + FLOW_H + 20
LEG_H   = 128
H       = LEG_Y + LEG_H + 40

# ---------------------------------------------------------------- document
add(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" '
    f'height="{H}" font-family="Inter, -apple-system, BlinkMacSystemFont, '
    f"'Segoe UI', Helvetica, Arial, sans-serif\">")
add('<defs>' + ''.join(
    f'<marker id="ar-{n}" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" '
    f'markerHeight="7" orient="auto-start-reverse">'
    f'<path d="M0,0 L10,5 L0,10 z" fill="{c["accent"]}"/></marker>'
    for n, c in STACKS.items()) + '</defs>')
add(f'<rect width="{W}" height="{H}" fill="{WHITE}"/>')

# -- header
text(56, 88, "AWS", size=54, weight="800", fill="#232f3e")
rrect(196, 44, 3, 56, 0, "#2563eb")
text(228, 86, "AWS resources created against floci", size=46, weight="800")
text(228, 124, "Every resource this project provisions, and how each behaves "
               "compared with real AWS.", size=23, fill="#2563eb")
text(56, 168, "The rule that predicts almost all of it: floci emulates the AWS control plane "
              "and delegates the data plane to real containers.", size=20, fill=MUTED)
text(56, 196, "Where a container backs the service fidelity is high; where none does, you get "
              "an object that records your intent and does nothing.", size=20, fill=MUTED)

bw, bh = 470, 96
rrect(W - 48 - bw, 40, bw, bh, 14, "#f8fafc", LINE, 2)
text(W - 48 - bw + 28, 82, "67 resources", size=32, weight="800")
text(W - 48 - bw + 28, 112, "32 distinct types  ·  4 Terragrunt stacks", size=19, fill=MUTED)

# -- panels
for name, px, pw in COLS:
    c = STACKS[name]
    count_label, panel_sub, blocks = CONTENT[name]
    rrect(px, PANEL_Y, pw, PANEL_H, 18, c["fill"], c["accent"], 3)

    add(f'<circle cx="{px + 46}" cy="{PANEL_Y + 46}" r="17" fill="{c["accent"]}"/>')
    add(f'<circle cx="{px + 46}" cy="{PANEL_Y + 46}" r="7" fill="{WHITE}"/>')
    text(px + 78, PANEL_Y + 56, name, size=32, weight="800", fill=c["deep"])
    text(px + 78, PANEL_Y + 84, f"{count_label}  ·  {panel_sub}", size=19, fill=MUTED)

    y = PANEL_Y + PANEL_HEAD + PANEL_PAD
    ix = px + PANEL_PAD
    iw = pw - PANEL_PAD * 2

    for i, b in enumerate(blocks):
        if i:
            y += SEC_GAP
        bh_ = block_height(b)
        kind = b[0]

        if kind == "sec":
            _, title, sub, rows, notes = b
            rrect(ix, y, iw, bh_, 12, WHITE, c["chip"], 2)
            text(ix + 18, y + 30, title, size=21, weight="700", fill=c["deep"])
            if sub:
                text(ix + 18, y + 30 + SEC_SUB_H - 4, sub, size=18, fill=MUTED)
            ry = y + SEC_TITLE_H + (SEC_SUB_H if sub else 0) + SEC_PAD - 8
            for rname, rcount, fid in rows:
                rrect(ix + 14, ry, iw - 28, ROW_H, 9, WHITE, LINE, 1.5)
                rrect(ix + 14, ry + 9, 6, ROW_H - 18, 3, FID[fid])
                size = 21 if len(rname) <= 34 else 16
                text(ix + 34, ry + ROW_H / 2 + 7, rname, size=size, weight="600")
                text(ix + iw - 42, ry + ROW_H / 2 + 7, rcount, size=22,
                     weight="800", fill=c["deep"], anchor="end")
                ry += ROW_H + ROW_GAP
            ny = ry + 14
            for ln in notes:
                text(ix + 20, ny, ln, size=18, fill=MUTED)
                ny += NOTE_LH

        elif kind == "split":
            halves = b[1]
            hw = (iw - 16) / 2
            for j, (htitle, lines) in enumerate(halves):
                hx = ix + j * (hw + 16)
                rrect(hx, y, hw, bh_, 12, WHITE, c["chip"], 2)
                text(hx + 18, y + 30, htitle, size=21, weight="700", fill=c["deep"])
                ly = y + BOX_TITLE_H + SEC_PAD + 12
                for ln in lines:
                    text(hx + 18, ly, ln, size=18, fill=BODY)
                    ly += NOTE_LH

        else:  # out / note / warn
            _, title, lines = b
            stroke = c["accent"] if kind == "warn" else c["chip"]
            sw = 2.5 if kind == "warn" else 2
            dash = ' stroke-dasharray="7 5"' if kind == "out" else ""
            add(f'<rect x="{ix:.0f}" y="{y:.0f}" width="{iw:.0f}" height="{bh_:.0f}" rx="12" '
                f'fill="{WHITE}" stroke="{stroke}" stroke-width="{sw}"{dash}/>')
            text(ix + 18, y + 30, title, size=20, weight="800", fill=c["deep"])
            ly = y + BOX_TITLE_H + SEC_PAD + 12
            for ln in lines:
                text(ix + 18, ly, ln, size=18, fill=BODY)
                ly += NOTE_LH

        y += bh_

# -- cross-stack flow: three independent edges
rrect(48, FLOW_Y, W - 96, FLOW_H, 14, "#f8fafc", LINE, 2)
text(76, FLOW_Y + 44, "CROSS-STACK FLOW", size=21, weight="800")
text(76, FLOW_Y + 76, "values move through a resolved: block folded", size=18, fill=MUTED)
text(76, FLOW_Y + 100, "into the YAML config — never through", size=18, fill=MUTED)
text(76, FLOW_Y + 124, "terraform_remote_state", size=18, fill=MUTED)

CHIP_W, CHIP_H, ARROW, EDGE_GAP = 240, 50, 250, 56
cy = FLOW_Y + FLOW_H / 2 + 24
ex = 560
for src, dst, label in FLOW:
    for k, nm in ((0, src), (1, dst)):
        cc = STACKS[nm]
        cxp = ex + k * (CHIP_W + ARROW)
        rrect(cxp, cy - CHIP_H / 2, CHIP_W, CHIP_H, 10, WHITE, cc["accent"], 2.5)
        text(cxp + CHIP_W / 2, cy + 8, nm, size=19, weight="800",
             fill=cc["deep"], anchor="middle")
    a0, a1 = ex + CHIP_W + 16, ex + CHIP_W + ARROW - 16
    ac = STACKS[src]["accent"]
    add(f'<line x1="{a0:.0f}" y1="{cy:.0f}" x2="{a1:.0f}" y2="{cy:.0f}" stroke="{ac}" '
        f'stroke-width="2.5" marker-end="url(#ar-{src})"/>')
    ly = cy - CHIP_H / 2 - 16 - (len(label) - 1) * 20
    for ln in label:
        text((a0 + a1) / 2, ly, ln, size=15, fill=MUTED, anchor="middle")
        ly += 20
    ex += CHIP_W * 2 + ARROW + EDGE_GAP

# -- fidelity legend + behaviour summary
rrect(48, LEG_Y, W - 96, LEG_H, 14, "#f8fafc", LINE, 2)
text(76, LEG_Y + 42, "FIDELITY", size=21, weight="800")
lx = 230
for key, label in LEGEND:
    rrect(lx, LEG_Y + 24, 9, 22, 4, FID[key])
    text(lx + 22, LEG_Y + 42, label, size=18, fill=BODY)
    lx += 40 + len(label) * 9.3

text(76, LEG_Y + 84, "BEHAVIOUR", size=21, weight="800")
sx = 230
for label, items, col in (
        ("Faithful:", "EKS · ECR · KMS · Secrets Manager · SSM", FID["faithful"]),
        ("Partial:", "RDS · S3 · IAM · ALB · ACM · VPC metadata", FID["partial"]),
        ("Broken:", "ElastiCache · CloudFront", FID["broken"])):
    rrect(sx, LEG_Y + 66, 9, 22, 4, col)
    text(sx + 22, LEG_Y + 84, label, size=18, weight="800", fill=INK)
    text(sx + 22 + len(label) * 10.4, LEG_Y + 84, items, size=18, fill=MUTED)
    sx += 60 + (len(label) * 10.4) + (len(items) * 9.3)

text(W - 76, LEG_Y + 84, "github.com/pronitaghosh/smart-floci-multicloud", size=18,
     fill=MUTED, anchor="end")
text(W - 76, LEG_Y + 42, "Counts, colours and flows describe the stack as applied.",
     size=18, fill=MUTED, anchor="end")

add('</svg>')
open(sys.argv[1], "w").write("\n".join(out) + "\n")
print(f"wrote {sys.argv[1]}  ({W}x{H})")
