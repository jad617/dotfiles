# kls: Kubernetes nodes and pods tables, with what is requested next to what is really used.
# kls --help for the options; tab completion at the bottom. Sourced by my_aliases.sh.

# Every pod as one tab-separated line: namespace, name, phase, "T" when terminating, node ("-" when not scheduled),
# creation time, QoS class, owner (kind/name), pod-template-hash label, then the containers' requests and limits
# ("cpu|mem|cpu|mem;"), the init containers' ("cpu|mem|cpu|mem|restartPolicy;"), the containers' statuses
# ("ready|restarts|waiting reason|terminated reason|last exit reason|last exit time;"), the init containers'
# ("ready|restarts|waiting reason|terminated reason|exit code;"), the pod's reason (Evicted...) and its labels ("k=v,").
_KLS_POD_TEMPLATE='{{range .items}}{{.metadata.namespace}}{{"\t"}}{{.metadata.name}}{{"\t"}}{{.status.phase}}{{"\t"}}{{with .metadata.deletionTimestamp}}T{{end}}{{"\t"}}{{or .spec.nodeName "-"}}{{"\t"}}{{.metadata.creationTimestamp}}{{"\t"}}{{or .status.qosClass "-"}}{{"\t"}}{{range .metadata.ownerReferences}}{{.kind}}/{{.name}}{{end}}{{"\t"}}{{with .metadata.labels}}{{or (index . "pod-template-hash") ""}}{{end}}{{"\t"}}{{range .spec.containers}}{{with .resources.requests}}{{.cpu}}|{{.memory}}{{else}}|{{end}}|{{with .resources.limits}}{{.cpu}}|{{.memory}}{{else}}|{{end}};{{end}}{{"\t"}}{{range .spec.initContainers}}{{with .resources.requests}}{{.cpu}}|{{.memory}}{{else}}|{{end}}|{{with .resources.limits}}{{.cpu}}|{{.memory}}{{else}}|{{end}}|{{.restartPolicy}};{{end}}{{"\t"}}{{range .status.containerStatuses}}{{.ready}}|{{.restartCount}}|{{with .state.waiting}}{{.reason}}{{end}}|{{with .state.terminated}}{{.reason}}{{end}}|{{with .lastState.terminated}}{{.reason}}|{{.finishedAt}}{{else}}|{{end}};{{end}}{{"\t"}}{{range .status.initContainerStatuses}}{{.ready}}|{{.restartCount}}|{{with .state.waiting}}{{.reason}}{{end}}|{{with .state.terminated}}{{.reason}}|{{.exitCode}}{{else}}|{{end}};{{end}}{{"\t"}}{{or .status.reason ""}}{{"\t"}}{{range $k, $v := .metadata.labels}}{{$k}}={{$v}},{{end}}{{"\n"}}{{end}}'

# Every node as one tab-separated line: its kind for the order (1 system, 2 nodegroup, 3 Karpenter, 4 other), name,
# status (Ready, NotReady or Unknown, plus SchedulingDisabled and any pressure condition), creation time,
# MANAGED-BY and GROUP, role, instance type, zone, kubelet version, nodegroup AMI ID, and allocatable pods, CPU and
# memory.
_KLS_NODE_TEMPLATE='{{range .items}}{{$l := .metadata.labels}}{{if eq (or (index $l "node-role") "") "system"}}1{{else if index $l "karpenter.sh/nodepool"}}3{{else if index $l "eks.amazonaws.com/nodegroup"}}2{{else}}4{{end}}{{"\t"}}{{.metadata.name}}{{"\t"}}{{range .status.conditions}}{{if eq .type "Ready"}}{{if eq .status "True"}}Ready{{else if eq .status "False"}}NotReady{{else}}Unknown{{end}}{{end}}{{end}}{{if .spec.unschedulable}},SchedulingDisabled{{end}}{{range .status.conditions}}{{if and (ne .type "Ready") (eq .status "True")}},{{.type}}{{end}}{{end}}{{"\t"}}{{.metadata.creationTimestamp}}{{"\t"}}{{if index $l "karpenter.sh/nodepool"}}karpenter{{"\t"}}{{index $l "karpenter.sh/nodepool"}}{{else if index $l "eks.amazonaws.com/nodegroup"}}nodegroup{{"\t"}}{{index $l "eks.amazonaws.com/nodegroup"}}{{else}}other{{"\t"}}-{{end}}{{"\t"}}{{or (index $l "node-role") "-"}}{{"\t"}}{{index $l "node.kubernetes.io/instance-type"}}{{"\t"}}{{index $l "topology.kubernetes.io/zone"}}{{"\t"}}{{.status.nodeInfo.kubeletVersion}}{{"\t"}}{{or (index $l "eks.amazonaws.com/nodegroup-image") "-"}}{{"\t"}}{{.status.allocatable.pods}}{{"\t"}}{{.status.allocatable.cpu}}{{"\t"}}{{.status.allocatable.memory}}{{"\n"}}{{end}}'

# Sorts _KLS_NODE_TEMPLATE lines into the nodes view order: system first, then nodegroups, Karpenter and the rest,
# each by group, then zone, then name.
_kls_sort_nodes() {
  sort -t $'\t' -k1,1n -k6,6 -k9,9
}

# Perl helpers shared by the formatters (put first in their code, so BEGIN blocks can use them):
# qty("250m"), qty("512Mi") to numbers; age(timestamp) like kubectl's AGE; pct(part, whole);
# fmt_cpu(cores) and fmt_mem(bytes) back to 250m / 1.5 and 512Mi / 1.2Gi;
# requests(containers, init containers) as the scheduler counts them: the larger of the containers plus sidecars
# (init containers that keep running) and of each other init container plus the sidecars started before it.
# It also returns the limits, undef when a container has none.
_KLS_PERL='
  sub qty {
    my %unit = (m => 1e-3, k => 1e3, M => 1e6, G => 1e9, T => 1e12, P => 1e15, E => 1e18,
                Ki => 2**10, Mi => 2**20, Gi => 2**30, Ti => 2**40, Pi => 2**50, Ei => 2**60);
    ($_[0] // "") =~ /^([0-9.]+(?:e[0-9]+)?)([a-zA-Z]*)$/ ? $1 * ($unit{$2} // 1) : 0;
  }
  sub has_qty { ($_[0] // "") =~ /^[0-9]/ }
  sub pct { $_[1] ? int(100 * $_[0] / $_[1]) . "%" : "-" }
  sub fmt_cpu { $_[0] < 1 ? int($_[0] * 1000 + 0.5) . "m" : sprintf("%.2f", $_[0]) =~ s/\.?0+$//r }
  sub fmt_mem {
    my $b = shift;
    $b >= 2**30 ? (sprintf("%.1f", $b / 2**30) =~ s/\.0$//r) . "Gi"
      : $b >= 2**20 ? int($b / 2**20 + 0.5) . "Mi"
      : int($b / 2**10 + 0.5) . "Ki";
  }
  sub age {
    return "-" unless ($_[0] // "") =~ /^(\d+)-(\d+)-(\d+)T(\d+):(\d+):(\d+)Z$/;
    my $s = time - timegm($6, $5, $4, $3, $2 - 1, $1);
    $s = 0 if $s < 0;
    my ($m, $h, $d) = (int($s / 60), int($s / 3600), int($s / 86400));
    my $y = int($d / 365);
    my $part = sub { my ($a, $ua, $b, $ub) = @_; $b ? "$a$ua$b$ub" : "$a$ua" };
    $s < 120       ? "${s}s"
      : $m < 10      ? $part->($m, "m", $s % 60, "s")
      : $h < 3       ? "${m}m"
      : $h < 8       ? $part->($h, "h", $m % 60, "m")
      : $h < 48      ? "${h}h"
      : $d < 8       ? $part->($d, "d", $h % 24, "h")
      : $d < 365 * 2 ? "${d}d"
      : $d < 365 * 8 ? $part->($y, "y", $d % 365, "d")
      :                "${y}y";
  }
  sub requests {
    my ($containers, $inits) = @_;
    my ($cpu, $mem, $lim_cpu, $lim_mem, $no_lim_cpu, $no_lim_mem) = (0) x 6;
    my ($side_cpu, $side_mem, $init_cpu, $init_mem) = (0) x 4;
    my $limits = sub {
      has_qty($_[0]) ? ($lim_cpu += qty($_[0])) : ($no_lim_cpu = 1);
      has_qty($_[1]) ? ($lim_mem += qty($_[1])) : ($no_lim_mem = 1);
    };
    for (split /;/, $containers // "") {
      my ($rc, $rm, $lc, $lm) = split /\|/, $_, -1;
      $cpu += qty($rc);
      $mem += qty($rm);
      $limits->($lc, $lm);
    }
    for (split /;/, $inits // "") {
      my ($rc, $rm, $lc, $lm, $policy) = split /\|/, $_, -1;
      if ($policy eq "Always") {
        $side_cpu += qty($rc);
        $side_mem += qty($rm);
        $limits->($lc, $lm);
      } else {
        $init_cpu = qty($rc) + $side_cpu if qty($rc) + $side_cpu > $init_cpu;
        $init_mem = qty($rm) + $side_mem if qty($rm) + $side_mem > $init_mem;
      }
    }
    $cpu += $side_cpu;
    $mem += $side_mem;
    $cpu = $init_cpu if $init_cpu > $cpu;
    $mem = $init_mem if $init_mem > $mem;
    ($cpu, $mem, $no_lim_cpu ? undef : $lim_cpu, $no_lim_mem ? undef : $lim_mem);
  }
'

kls() {
  local -a args
  local i mode=nodes interval= summary= out color=${KLS_COLOR:-0}
  [[ -z "$KLS_COLOR" && -t 1 && -z "$NO_COLOR" ]] && color=1
  for (( i = 1; i <= $#; i++ )); do
    case "${@[i]}" in
      -h|--help) _kls_help; return 0 ;;
      --nodes) mode=nodes ;;
      --pods) mode=pods ;;
      --summary) summary=--summary ;;
      --watch=*) interval=${@[i]#--watch=} ;;
      --watch)
        interval=2
        if [[ "${@[i+1]}" =~ '^[0-9]+([.][0-9]+)?$' ]]; then
          interval=${@[i+1]}
          (( i++ ))
        fi
        ;;
      *) args+=("${@[i]}") ;;
    esac
  done
  if [[ -n "$interval" ]]; then
    if [[ ! "$interval" =~ '^[0-9]+([.][0-9]+)?$' ]] || (( interval <= 0 )); then
      print -u2 "kls: --watch needs a positive number of seconds, got '$interval'"
      return 1
    fi
    while true; do
      # Build the table before clearing, so the screen doesn't flash empty while kubectl runs.
      out=$(KLS_COLOR=$color kls --$mode $summary "${args[@]}" 2>&1)
      printf '\e[H\e[2J'
      if (( color )); then
        print -r -- $'\e[1m'"Every ${interval}s: kls --$mode ${summary:+$summary }${args[*]}"$'\e[0m    \e[2m'"$(date '+%H:%M:%S')"$'\e[0m'
      else
        print -r -- "Every ${interval}s: kls --$mode ${summary:+$summary }${args[*]}    $(date '+%H:%M:%S')"
      fi
      print
      print -r -- "$out"
      sleep "$interval" || return
    done
  fi
  KLS_SUMMARY=$summary "_kls_$mode" "$color" "${args[@]}"
}

_kls_help() {
  cat <<'EOF'
kls - Kubernetes nodes and pods, with what is requested next to what is really used

Usage:
  kls [--nodes] [--watch [N]] [kubectl options]
  kls --pods [--node [NODE]] [--watch [N]] [kubectl options]

Views:
  --nodes        Nodes, system first, then nodegroups, Karpenter and the rest (the default): status, pods
                 (all, then developer apps and system ones: DaemonSets, kube-* and the namespaces
                 hidden from developers), CPU and memory requested/used % of allocatable, age, owner, instance, zone,
                 kubelet and AMI versions, and a summary per group with --summary.
  --pods         Pods in the namespaces developers can read (see below): ready, HPA replicas (current/max), PDB
                 (disruptions allowed and its rule), status, restarts with the last exit reason, CPU and
                 memory request/limit and used (with % of the request/limit), QoS, age and node, a summary
                 per namespace with --summary, and the HPAs at their max and PDBs blocking drains.

Options:
  --summary      Add the summary table: per group with --nodes, per namespace with --pods.
  --watch [N]    Redraw every N seconds (2 by default) until Ctrl+C. Also --watch=N.
  --node         With --pods: group the pods by node, under a line with the node name.
  --node NODE    With --pods: only the pods on that node. Also --node=NODE.
  --all          With --pods: also the namespaces hidden from developers (see below), like -A.
  -h, --help     Show this help.
  Anything else goes to kubectl: --context NAME, -n NAMESPACE, -A, -l SELECTOR, --field-selector...

With --pods and no -n, -A or --all, only the namespaces developers can read are shown: those with a
RoleBinding labelled app.kubernetes.io/managed-by=read-only-namespaces (or every namespace without them).

Used numbers come from metrics-server (kubectl top) and show "-" without it.
Colored on a terminal; set NO_COLOR for plain text.

Examples:
  kls --watch 5
  kls --summary
  kls --pods --summary
  kls --pods -n kube-system
  kls --pods --all
  kls --pods --node
  kls --pods --node NODE --watch
  kls --pods -l app=api --context staging
EOF
}

# Sets $reply to the cluster-selection args in "$@" (--context, --kubeconfig, --cluster, --user), which apply to
# every lookup, unlike selectors and namespaces.
_kls_conn() {
  local i
  reply=()
  for (( i = 1; i <= $#; i++ )); do
    case "${@[i]}" in
      --context=*|--kubeconfig=*|--cluster=*|--user=*) reply+=("${@[i]}") ;;
      --context|--kubeconfig|--cluster|--user) reply+=("${@[i]}" "${@[i+1]}") ;;
    esac
  done
}

# Prints the output of a formatter, with the header $2 (tab-separated) on its rows: the rows, then after a
# "--summary--" line the summary table (shown when KLS_SUMMARY is set), then after a "--notes--" line lines to
# print as they are.
_kls_print() {
  local color=$1 header=$2 out
  out=$(cat)
  {
    print -r -- "$header"
    print -r -- "${out%%$'\n'--summary--*}"
  } | KLS_COLOR=$color _kls_table
  out=${out#*--summary--$'\n'}
  if [[ -n "$KLS_SUMMARY" ]]; then
    print
    print -r -- "${out%%$'\n'--notes--*}" | KLS_COLOR=$color _kls_table
  fi
  out=${out#*--notes--}
  if [[ -n "$out" ]]; then
    print
    print -r -- "${out#$'\n'}"
  fi
  return 0
}

# Prints the namespaces developers can read, one per line: those with a RoleBinding labelled
# app.kubernetes.io/managed-by=read-only-namespaces, which the kube-system/read-only-namespaces CronJob creates in
# every namespace but the ones in its HIDDEN_NAMESPACES. "*" (all of them) on a cluster without those bindings.
_kls_visible() {
  kubectl get rolebindings --all-namespaces "$@" -l app.kubernetes.io/managed-by=read-only-namespaces \
    -o go-template='{{range .items}}{{.metadata.namespace}}{{"\n"}}{{end}}' 2>/dev/null | grep . || print '*'
}

# Nodes view. The AMI ID comes from the managed nodegroup label, or from the Karpenter NodeClaim for Karpenter nodes;
# its version (1.35-v20261112) from the AMI name, read with the cluster's AWS profile. The ID shows if that fails.
# AMI names never change, so they are cached in ~/.cache/kls/ami-names and only new IDs are looked up.
_kls_nodes() {
  local color=$1
  shift
  local -a conn ids cached missing reply
  local rows pods amis usage profile region names cache out pods_fd claims_fd top_fd visible visible_fd
  _kls_conn "$@"
  conn=("${reply[@]}")
  # The pods, NodeClaims and usage lookups run in the background while the nodes one runs, since each kubectl call
  # spends most of its time getting a token. Pods are the ones not Succeeded or Failed, like kubectl describe node.
  exec {pods_fd}< <(kubectl get pods --all-namespaces "${conn[@]}" \
    --field-selector=status.phase!=Succeeded,status.phase!=Failed -o go-template="$_KLS_POD_TEMPLATE" 2>/dev/null)
  exec {visible_fd}< <(_kls_visible "${conn[@]}")
  exec {claims_fd}< <(kubectl get nodeclaims "${conn[@]}" \
    -o go-template='{{range .items}}{{.status.nodeName}}{{"\t"}}{{.status.imageID}}{{"\n"}}{{end}}' 2>/dev/null)
  exec {top_fd}< <(kubectl top nodes --no-headers "${conn[@]}" 2>/dev/null | awk '{print $1 "\t" $2 "\t" $4}')
  rows=$(kubectl get nodes "$@" -o go-template="$_KLS_NODE_TEMPLATE" | _kls_sort_nodes | cut -f2-)
  pods=$(cat <&$pods_fd)
  visible=$(cat <&$visible_fd)
  amis=$(cat <&$claims_fd)
  usage=$(cat <&$top_fd)
  exec {pods_fd}<&- {claims_fd}<&- {top_fd}<&- {visible_fd}<&-
  pods=$(print -r -- "$pods" | KLS_VISIBLE="$visible" _kls_node_pods)
  # kubectl has already said why when there are no nodes (an error, or "No resources found").
  [[ -n "$rows" ]] || return 1
  cache=${XDG_CACHE_HOME:-$HOME/.cache}/kls/ami-names
  [[ -f "$cache" ]] && names=$(<"$cache")
  ids=(${(u)$(print -r -- "$rows" | cut -f10; print -r -- "$amis" | cut -f2)})
  ids=(${(M)ids:#ami-*})
  cached=(${${(f)names}%%$'\t'*})
  missing=(${ids:|cached})
  if (( ${#missing} )); then
    profile=$(kubectl config view --minify "${conn[@]}" -o jsonpath='{.users[0].user.exec.env[?(@.name=="AWS_PROFILE")].value}' 2>/dev/null)
    region=$(print -r -- "$rows" | head -1 | cut -f8 | sed 's/[a-z]$//')
    out=$(env ${profile:+AWS_PROFILE=$profile} aws ec2 describe-images --region "$region" --image-ids "${missing[@]}" \
      --query 'Images[].[ImageId,Name]' --output text 2>/dev/null)
    if [[ -n "$out" ]]; then
      mkdir -p "${cache:h}" && print -r -- "$out" >> "$cache"
      names+=$'\n'$out
    fi
  fi
  print -r -- "$rows" | KLS_PODS="$pods" KLS_AMIS="$amis" KLS_USAGE="$usage" KLS_NAMES="$names" _kls_nodes_format \
    | _kls_print "$color" $'NAME\tSTATUS\tAGE\tPODS\tAPPS\tSYSTEM\tCPU REQ/USED\tMEM REQ/USED\tMANAGED-BY\tGROUP\tROLE\tINSTANCE\tZONE\tVERSION\tAMI'
}

# Reads _KLS_POD_TEMPLATE lines and prints "node<TAB>pods<TAB>system pods<TAB>cpu cores<TAB>memory bytes" per
# node, with "-" as the node of the pods not scheduled yet. System pods are the DaemonSet and static ones (owned by
# their Node), and every pod in a kube-* namespace or in one hidden from developers (missing from the lines of
# $KLS_VISIBLE, "*" for none hidden).
_kls_node_pods() {
  perl -MTime::Local -F'\t' -lane "$_KLS_PERL"'
    BEGIN { %visible = map { $_ => 1 } split /\n/, $ENV{KLS_VISIBLE} || "*" }
    my ($cpu, $mem) = requests($F[9], $F[10]);
    $n{$F[4]}++;
    $d{$F[4]} += $F[7] =~ m{^(DaemonSet|Node)/} || $F[0] =~ /^kube-/ || !($visible{"*"} || $visible{$F[0]}) ? 1 : 0;
    $c{$F[4]} += $cpu;
    $b{$F[4]} += $mem;
    END { print join "\t", $_, $n{$_}, $d{$_}, $c{$_}, $b{$_} for sort keys %n }'
}

# Turns the creation timestamp in the 3rd column into an age,
# fills a missing AMI ID (10th column) from the "node<TAB>ami" lines in $KLS_AMIS, then replaces it with
# the version in its name, from the "ami<TAB>name" lines in $KLS_NAMES. The last three columns (allocatable pods,
# CPU and memory) become "running/allocatable" pods and requested/used %, from the _kls_node_pods lines in
# $KLS_PODS and the "node<TAB>cpu<TAB>memory" lines in $KLS_USAGE, and move after AGE, with the developer application
# and system pod counts after the pods.
# Then a summary row per group (MANAGED-BY and GROUP, in table order) plus a TOTAL row,
# and the count of pods not on a node yet, if any (see _kls_print).
_kls_nodes_format() {
  perl -MTime::Local -F'\t' -lane "$_KLS_PERL"'
    BEGIN {
      for (split /\n/, $ENV{KLS_PODS} // "") {
        my ($node, @v) = split /\t/;
        $pods{$node} = [@v];
      }
      for (split /\n/, $ENV{KLS_USAGE} // "") {
        my ($node, @v) = split /\t/;
        $used{$node} = [map { qty($_) } @v] if has_qty($v[0]);
      }
      %ami  = map { split /\t/ } grep { /\t./ } split /\n/, $ENV{KLS_AMIS}  // "";
      %name = map { split /\t/ } grep { /\t./ } split /\n/, $ENV{KLS_NAMES} // "";
    }
    # "requested/used" % for a node or group hash, with "-" as the used part when there are no metrics.
    sub req_used { my ($t, $k) = @_; pct($t->{$k}, $t->{"alloc_$k"}) . "/" . pct($t->{"used_$k"}, $t->{"metered_$k"}) }
    $F[2] = age($F[2]);
    $F[9] = $ami{$F[0]} if $F[9] eq "-" && $ami{$F[0]};
    $F[9] = $1 if ($name{$F[9]} // "") =~ /-(\d+\.\d+-v\d+)$/;
    my ($n, $system, $cpu, $mem) = @{ $pods{$F[0]} // [0, 0, 0, 0] };
    my %node = (
      nodes      => 1,
      pods       => $n,
      apps       => $n - $system,
      system     => $system,
      alloc_pods => $F[10] || 0,
      cpu        => $cpu,
      mem        => $mem,
      alloc_cpu  => qty($F[11]),
      alloc_mem  => qty($F[12]),
      cordoned   => $F[1] =~ /SchedulingDisabled/ ? 1 : 0,
      notready   => $F[1] =~ /^Ready/ ? 0 : 1,
    );
    if (my $u = $used{$F[0]}) {
      @node{qw(used_cpu used_mem metered_cpu metered_mem)} = (@$u, $node{alloc_cpu}, $node{alloc_mem});
    }
    $F[10] = $n . "/" . ($F[10] || "?");
    $F[11] = req_used(\%node, "cpu");
    $F[12] = req_used(\%node, "mem");
    splice @F, 11, 0, $node{apps}, $node{system};
    my $group = "$F[3]\t$F[4]";
    push @groups, $group unless $sum{$group};
    for my $t ($sum{$group} //= {}, $total //= {}) {
      $t->{$_} += $node{$_} for keys %node;
    }
    splice @F, 3, 0, splice(@F, 10);
    print join "\t", @F;
    END {
      print "--summary--";
      print join "\t", "MANAGED-BY", "GROUP", "NODES", "PODS", "APPS", "SYSTEM", "CPU REQ/USED", "MEM REQ/USED", "CORDONED", "NOT READY";
      for my $g (@groups, "TOTAL\t-") {
        my $t = $g =~ /^TOTAL\t/ ? $total : $sum{$g};
        print join "\t", $g, $t->{nodes}, "$t->{pods}/$t->{alloc_pods}", $t->{apps} || 0, $t->{system} || 0, req_used($t, "cpu"), req_used($t, "mem"),
          $t->{cordoned} || 0, $t->{notready} || 0;
      }
      print "--notes--";
      my $pending = $pods{"-"} ? $pods{"-"}[0] : 0;
      print "$pending pod" . ($pending == 1 ? "" : "s") . " not on a node yet" if $pending;
    }'
}

# Pods view. --node alone groups the pods by node, under a line with the node name. --node NODE (or --node=NODE) becomes a
# spec.nodeName field selector, merged with any --field-selector given.
# Without -n, -A or --all, only the namespaces developers can read (see _kls_visible) are shown.
_kls_pods() {
  local color=$1
  shift
  local -a get conn fields reply
  local i rows usage top_fd namespaced= all= by_node=0
  local hpas pdbs hpa_fd pdb_fd visible visible_fd nodes= nodes_fd
  local header=$'NAMESPACE\tNAME\tREADY\tHPA\tPDB\tSTATUS\tAGE\tRESTARTS\tCPU REQ/LIM\tCPU USED %REQ/LIM\tMEM REQ/LIM\tMEM USED %REQ/LIM\tQOS\tNODE'
  for (( i = 1; i <= $#; i++ )); do
    case "${@[i]}" in
      --node=?*) fields+=("spec.nodeName=${@[i]#--node=}") ;;
      --node=) by_node=1 ;;
      --node)
        if [[ -n "${@[i+1]}" && "${@[i+1]}" != -* ]]; then
          fields+=("spec.nodeName=${@[i+1]}")
          (( i++ ))
        else
          by_node=1
        fi
        ;;
      --field-selector=*) fields+=("${@[i]#--field-selector=}") ;;
      --field-selector) fields+=("${@[i+1]}"); (( i++ )) ;;
      -n|--namespace|-n?*|--namespace=*|-A|--all-namespaces) namespaced=1; get+=("${@[i]}") ;;
      --all) all=1 ;;
      *) get+=("${@[i]}") ;;
    esac
  done
  [[ -n "$namespaced" ]] || get+=(--all-namespaces)
  (( ${#fields} )) && get+=(--field-selector="${(j:,:)fields}")
  _kls_conn "$@"
  conn=("${reply[@]}")
  # With --node: each node's name, MANAGED-BY and GROUP, as in the nodes view.
  if (( by_node )); then
    exec {nodes_fd}< <(kubectl get nodes "${conn[@]}" -o go-template="$_KLS_NODE_TEMPLATE" 2>/dev/null \
      | _kls_sort_nodes | cut -f2,5,6)
  fi
  # "*" when every namespace is to be shown.
  if [[ -n "$namespaced$all" ]]; then
    exec {visible_fd}< <(print '*')
  else
    exec {visible_fd}< <(_kls_visible "${conn[@]}")
  fi
  exec {top_fd}< <(kubectl top pods --all-namespaces --no-headers "${conn[@]}" 2>/dev/null \
    | awk '{print $1 "\t" $2 "\t" $3 "\t" $4}')
  # HPAs: namespace, target kind and name, current, max and min replicas.
  exec {hpa_fd}< <(kubectl get hpa --all-namespaces "${conn[@]}" -o go-template='{{range .items}}{{.metadata.namespace}}{{"\t"}}{{.spec.scaleTargetRef.kind}}{{"\t"}}{{.spec.scaleTargetRef.name}}{{"\t"}}{{or .status.currentReplicas 0}}{{"\t"}}{{.spec.maxReplicas}}{{"\t"}}{{or .spec.minReplicas 1}}{{"\n"}}{{end}}' 2>/dev/null)
  # PDBs: namespace, name, selector kind (A: empty, matches every pod; S: set; N: none, matches no pod), its
  # matchLabels ("k=v,") and matchExpressions ("key|operator|v1,v2,;"), minAvailable, maxUnavailable and the
  # disruptions allowed now.
  exec {pdb_fd}< <(kubectl get pdb --all-namespaces "${conn[@]}" -o go-template='{{range .items}}{{.metadata.namespace}}{{"\t"}}{{.metadata.name}}{{"\t"}}{{if eq (printf "%v" .spec.selector) "map[]"}}A{{else if .spec.selector}}S{{else}}N{{end}}{{"\t"}}{{with .spec.selector}}{{range $k, $v := .matchLabels}}{{$k}}={{$v}},{{end}}{{"\t"}}{{range .matchExpressions}}{{.key}}|{{.operator}}|{{range .values}}{{.}},{{end}};{{end}}{{else}}{{"\t"}}{{end}}{{"\t"}}{{or .spec.minAvailable ""}}{{"\t"}}{{or .spec.maxUnavailable ""}}{{"\t"}}{{or .status.disruptionsAllowed 0}}{{"\n"}}{{end}}' 2>/dev/null)
  rows=$(kubectl get pods "${get[@]}" -o go-template="$_KLS_POD_TEMPLATE")
  usage=$(cat <&$top_fd)
  hpas=$(cat <&$hpa_fd)
  pdbs=$(cat <&$pdb_fd)
  visible=$(cat <&$visible_fd)
  exec {top_fd}<&- {hpa_fd}<&- {pdb_fd}<&- {visible_fd}<&-
  if (( by_node )); then
    nodes=$(cat <&$nodes_fd)
    exec {nodes_fd}<&-
  fi
  # kubectl has already said why when there are no pods (an error, or "No resources found").
  [[ -n "$rows" ]] || return 1
  (( by_node )) && header=${header/$'\tNODE'/}
  print -r -- "$rows" | KLS_USAGE="$usage" KLS_HPAS="$hpas" KLS_PDBS="$pdbs" KLS_VISIBLE="$visible" KLS_NODES="$nodes" \
    KLS_BY_NODE=$by_node _kls_pods_format \
    | _kls_print "$color" "$header"
}

# Reads _KLS_POD_TEMPLATE lines, the "namespace<TAB>pod<TAB>cpu<TAB>memory" lines in $KLS_USAGE and the HPA and
# PDB lines in $KLS_HPAS and $KLS_PDBS (see _kls_pods), and prints a row per pod: the HPA of its owner as
# current/max replicas, the PDB matching its labels as the disruptions allowed and its rule, status like kubectl's
# (the pod reason, an init container problem, a waiting or terminated reason, else the phase), restarts with the
# last exit reason and when, and request/limit and used with % of the request and of the limit. The owner (a ReplicaSet as its
# Deployment) is only used to find the HPA. With KLS_BY_NODE=1 the rows are grouped by node instead, under a
# "## node (N pods, MANAGED-BY: GROUP)" line, from the "node<TAB>managed-by<TAB>group" lines in $KLS_NODES, in their
# order, with no NODE column.
# Pods in a namespace missing from the lines of $KLS_VISIBLE ("*" for all) are left out and counted in a note.
# Then a summary row per namespace plus a TOTAL row (pods Succeeded or Failed only count in PODS),
# and notes: the pods not Running or Completed by status, HPAs at their max and PDBs allowing no disruption
# (see _kls_print).
_kls_pods_format() {
  perl -MTime::Local -F'\t' -lane "$_KLS_PERL"'
    BEGIN {
      for (split /\n/, $ENV{KLS_USAGE} // "") {
        my ($ns, $pod, $c, $m) = split /\t/;
        $used{"$ns/$pod"} = [qty($c), qty($m)] if has_qty($c);
      }
      my %short = (Deployment => "deploy", StatefulSet => "sts", ReplicaSet => "rs");
      for (split /\n/, $ENV{KLS_HPAS} // "") {
        my ($ns, $kind, $name, $current, $max, $min) = split /\t/;
        $hpa{"$ns/" . ($short{$kind} // lc $kind) . "/$name"} = [$current, $max, $min];
      }
      for (split /\n/, $ENV{KLS_PDBS} // "") {
        my ($ns, $name, $selector, $labels, $exprs, $min, $max, $allowed) = split /\t/, $_, -1;
        push @{ $pdbs{$ns} }, {
          name     => $name,
          selector => $selector,
          labels   => { map { split /=/, $_, 2 } split /,/, $labels },
          exprs    => [map { my ($k, $op, $v) = split /\|/, $_, -1; [$k, $op, { map { $_ => 1 } split /,/, $v }] } split /;/, $exprs],
          rule     => $min ne "" ? "min $min" : $max ne "" ? "unavail $max" : "-",
          allowed  => $allowed,
        };
      }
    }
    # The usage of a pod with its % of the request and of the limit ("133Mi 266%/44%", "-" for a missing one).
    sub used {
      my ($u, $req, $lim, $fmt) = @_;
      return "-" unless defined $u;
      return $fmt->($u) unless $req || $lim;
      $fmt->($u) . " " . pct($u, $req) . "/" . pct($u, $lim);
    }
    # A namespace usage with its % of the requests.
    sub used_req { my ($u, $req, $fmt) = @_; $fmt->($u) . ($req ? " " . pct($u, $req) : "") }
    sub req_lim { my ($req, $lim, $fmt) = @_; ($req ? $fmt->($req) : "-") . "/" . (defined $lim ? $fmt->($lim) : "-") }
    # Whether a PDB selects a pod with these labels (a hash ref), like a label selector does.
    sub selects {
      my ($p, $l) = @_;
      return $p->{selector} eq "A" if $p->{selector} ne "S";
      for (keys %{ $p->{labels} }) {
        return 0 unless defined $l->{$_} && $l->{$_} eq $p->{labels}{$_};
      }
      for (@{ $p->{exprs} }) {
        my ($k, $op, $in) = @$_;
        return 0 if $op eq "In" && !(defined $l->{$k} && $in->{ $l->{$k} });
        return 0 if $op eq "NotIn" && defined $l->{$k} && $in->{ $l->{$k} };
        return 0 if $op eq "Exists" && !exists $l->{$k};
        return 0 if $op eq "DoesNotExist" && exists $l->{$k};
      }
      1;
    }
    my ($ns, $pod, $phase, $deleting, $node, $created, $qos, $owner, $hash, $spec, $init_spec, $statuses, $init_statuses, $reason, $labels) = @F;
    %visible = map { $_ => 1 } split /\n/, $ENV{KLS_VISIBLE} // "*" unless %visible;
    unless ($visible{"*"} || $visible{$ns}) {
      $hidden{$ns}++;
      next;
    }
    my %labels = map { split /=/, $_, 2 } split /,/, $labels // "";
    my @cs = map { [split /\|/, $_, -1] } split /;/, $statuses // "";
    my @is = map { [split /\|/, $_, -1] } split /;/, $init_statuses // "";
    my $status = $reason || $phase;
    unless ($reason) {
      my ($init) = map { $_->[2] && $_->[2] ne "PodInitializing" ? "Init:$_->[2]" : $_->[3] && $_->[4] ne "0" ? "Init:$_->[3]" : () } @is;
      my ($waiting) = grep { $_ } map { $_->[2] } @cs;
      my ($terminated) = grep { $_ } map { $_->[3] } @cs;
      my $running = grep { !$_->[2] && !$_->[3] } @cs;
      $status = $init // $waiting // ($terminated && !($running && $terminated eq "Completed") ? $terminated : $status);
    }
    $status = "Terminating" if $deleting;
    my $ready = grep { $_->[0] eq "true" } @cs;
    my @spec = split /;/, $spec // "";
    my $containers = @spec;
    my $restarts = 0;
    $restarts += $_->[1] for @cs, @is;
    my ($last) = sort { $b->[5] cmp $a->[5] } grep { $_->[4] } @cs;
    my $restart_cell = $restarts . ($last ? " ($last->[4], " . age($last->[5]) . " ago)" : "");
    my ($cpu, $mem, $lim_cpu, $lim_mem) = requests($spec, $init_spec);
    my $u = $used{"$ns/$pod"};
    my ($kind, $name) = split m{/}, $owner // "", 2;
    my %short = (ReplicaSet => "rs", StatefulSet => "sts", DaemonSet => "ds", Job => "job", Node => "node");
    if ($kind eq "ReplicaSet" && $hash && $name =~ s/-\Q$hash\E$//) {
      $kind = "deploy";
    } else {
      $kind = $short{$kind} // lc $kind;
    }
    my $h = $owner ? $hpa{"$ns/$kind/$name"} : undef;
    $hpa_at_max{"$ns/$kind/$name"} = "$h->[0]/$h->[1]" if $h && $h->[0] >= $h->[1];
    # Several PDBs on one pod make its eviction fail; show the one allowing the fewest disruptions.
    my ($p) = sort { $a->{allowed} <=> $b->{allowed} } grep { selects($_, \%labels) } @{ $pdbs{$ns} // [] };
    $pdb_blocking{"$ns/$p->{name}"} = $p->{rule} if $p && !$p->{allowed};
    my @row = ($ns, $pod, "$ready/$containers", $h ? "$h->[0]/$h->[1]" : "-",
      $p ? "$p->{allowed} allowed ($p->{rule})" : "-", $status, age($created), $restart_cell,
      req_lim($cpu, $lim_cpu, \&fmt_cpu), used($u && $u->[0], $cpu, $lim_cpu, \&fmt_cpu),
      req_lim($mem, $lim_mem, \&fmt_mem), used($u && $u->[1], $mem, $lim_mem, \&fmt_mem),
      $qos);
    if ($ENV{KLS_BY_NODE}) {
      push @by_node, [$node, @row];
    } else {
      print join "\t", @row, $node;
    }
    push @namespaces, $ns unless $sum{$ns};
    my $active = $phase ne "Succeeded" && $phase ne "Failed";
    my %pod = (
      pods     => 1,
      notready => $active && $ready < $containers ? 1 : 0,
      restarts => $restarts,
      cpu      => $active ? $cpu : 0,
      mem      => $active ? $mem : 0,
    );
    if ($u) {
      @pod{qw(used_cpu used_mem metered)} = (@$u, 1);
    }
    for my $t ($sum{$ns} //= {}, $total //= {}) {
      $t->{$_} += $pod{$_} for keys %pod;
    }
    $not_running{$status}++ unless $status eq "Running" || $status eq "Completed";
    END {
      # By node: a "## node (N pods, MANAGED-BY: GROUP)" section line per node (pods not scheduled yet last), then its pods by
      # namespace and name.
      # KLS_NODES is in the nodes view order; nodes missing from it come after, pods not scheduled yet last.
      my (%owners, %rank);
      for (split /\n/, $ENV{KLS_NODES} // "") {
        my ($n, @o) = split /\t/;
        $owners{$n} = [@o];
        $rank{$n} = keys %rank;
      }
      my %on;
      push @{ $on{ $_->[0] } }, [@$_[1 .. $#$_]] for @by_node;
      for my $node (sort { ($a eq "-") <=> ($b eq "-") || ($rank{$a} // 1e9) <=> ($rank{$b} // 1e9) || $a cmp $b } keys %on) {
        my @pods = sort { $a->[0] cmp $b->[0] || $a->[1] cmp $b->[1] } @{ $on{$node} };
        my $owner = $owners{$node} ? ", $owners{$node}[0]: $owners{$node}[1]" : "";
        print "## " . ($node eq "-" ? "not on a node" : $node) . " (" . @pods . " pod" . (@pods == 1 ? "" : "s") . "$owner)";
        print join "\t", @$_ for @pods;
      }
      print "--summary--";
      print join "\t", "NAMESPACE", "PODS", "NOT READY", "RESTARTS", "CPU REQ", "CPU USED", "MEM REQ", "MEM USED";
      for my $ns (@namespaces, "TOTAL") {
        my $t = $ns eq "TOTAL" ? $total : $sum{$ns};
        print join "\t", $ns, $t->{pods}, $t->{notready}, $t->{restarts},
          $t->{cpu} ? fmt_cpu($t->{cpu}) : "-", $t->{metered} ? used_req($t->{used_cpu}, $t->{cpu}, \&fmt_cpu) : "-",
          $t->{mem} ? fmt_mem($t->{mem}) : "-", $t->{metered} ? used_req($t->{used_mem}, $t->{mem}, \&fmt_mem) : "-";
      }
      print "--notes--";
      print "Not running: " . join ", ", map { "$not_running{$_} $_" } sort keys %not_running if %not_running;
      print "HPAs at max replicas: " . join ", ", map { "$_ $hpa_at_max{$_}" } sort keys %hpa_at_max if %hpa_at_max;
      print "PDBs allowing no disruption (they block drains): " . join ", ", map { "$_ ($pdb_blocking{$_})" } sort keys %pdb_blocking
        if %pdb_blocking;
      if (%hidden) {
        my $n = 0;
        $n += $_ for values %hidden;
        print "Hidden from developers, --all to show: $n pod" . ($n == 1 ? "" : "s") . " in " . join ", ", sort keys %hidden;
      }
    }'
}

# Lines up the tab-separated rows on stdin (the first one the header) in columns two spaces apart, like
# column -t, but measuring the text without its color codes. A "## text" line is a section title, printed after a
# blank line. With KLS_COLOR=1 it colors them: a bold header,
# STATUS (Ready and Running green, cordoned and starting or stopping yellow, Completed dimmed, anything else red),
# READY when not all containers are, PODS and REQ/USED % at 70% yellow and 90% red, HPA replicas at 80% of the max
# yellow and at the max red, a PDB allowing no disruption red, USED % of the request yellow from 100% and of the
# limit yellow from 75% and red from 90%, RESTARTS (OOMKilled red), BestEffort QoS, MANAGED-BY, system nodes, an AMI version
# older than the newest one listed, nonzero CORDONED and NOT READY, TOTAL in bold, and "-" dimmed.
_kls_table() {
  perl -F'\t' -lane '
    push @rows, [@F];
    sub paint { my ($s, $code) = @_; $code ? "\e[${code}m$s\e[0m" : $s }
    sub level { $_[0] >= 90 ? 31 : $_[0] >= 70 ? 33 : "" }
    sub cell {
      my ($name, $v, $row) = @_;
      return paint($v, 2) if $v eq "-";
      return paint($v, 1) if $v eq "TOTAL";
      if ($name eq "STATUS") {
        return join ",", map {
          paint($_, /^(Ready|Running)$/ ? 32 : /^Completed$/ ? 2
            : /^(SchedulingDisabled|Pending|ContainerCreating|PodInitializing|Terminating)$/ ? 33 : 31)
        } split /,/, $v;
      }
      if ($name =~ /REQ\/USED/) {
        $v =~ s{(\d+)%}{paint("$1%", level($1))}ge;
        $v =~ s{/-$}{"/" . paint("-", 2)}e;
        return $v;
      }
      if ($name =~ / USED/) {
        # "133Mi 266%/44%": % of the request yellow from 100%, % of the limit yellow from 75% and red from 90%.
        if ($v =~ m{^(\S+) (\S+)/(\S+)$}) {
          my ($used, $req, $lim) = ($1, $2, $3);
          $req = $req eq "-" ? paint($req, 2) : paint($req, ($req =~ /(\d+)/)[0] >= 100 ? 33 : "");
          $lim = $lim eq "-" ? paint($lim, 2) : paint($lim, ($lim =~ /(\d+)/)[0] >= 90 ? 31 : ($lim =~ /(\d+)/)[0] >= 75 ? 33 : "");
          return "$used $req/$lim";
        }
        # A summary "6.5Gi 57%": % of the requests yellow from 100%.
        $v =~ s{(\d+)%}{paint("$1%", $1 >= 100 ? 33 : "")}ge;
        return $v;
      }
      if ($name eq "READY" && $v =~ m{^(\d+)/(\d+)$}) {
        return paint($v, $row->{STATUS} eq "Completed" ? 2 : $1 < $2 ? 31 : "");
      }
      return paint($v, level(100 * $1 / $2)) if $name eq "PODS" && $v =~ m{^(\d+)/(\d+)$} && $2;
      return paint($v, $1 >= $2 ? 31 : $1 >= 0.8 * $2 ? 33 : "") if $name eq "HPA" && $v =~ m{^(\d+)/(\d+)$} && $2;
      return paint($v, $v =~ /^0 / ? 31 : "") if $name eq "PDB";
      return paint($v, $v =~ /OOMKilled/ ? 31 : $v =~ /^0\b/ ? 2 : 33) if $name eq "RESTARTS";
      return paint($v, 33) if $name eq "QOS" && $v eq "BestEffort";
      return paint($v, { karpenter => 35, nodegroup => 34 }->{$v}) if $name eq "MANAGED-BY";
      return paint($v, 36) if $name eq "ROLE" && $v eq "system";
      return paint($v, $v =~ /^ami-/ ? 2 : $newest_ami && $v ne $newest_ami ? 33 : "") if $name eq "AMI";
      return paint($v, $v ? 33 : 2) if $name eq "CORDONED";
      return paint($v, $v ? 31 : 2) if $name eq "NOT READY";
      return $v;
    }
    END {
      my @head = @{ $rows[0] };
      my @width;
      my @cells = grep { $_->[0] !~ /^## / } @rows;
      for my $r (@cells) {
        for (0 .. $#$r) {
          $width[$_] = length $r->[$_] if length $r->[$_] > ($width[$_] // 0);
        }
      }
      my ($ami) = grep { $head[$_] eq "AMI" } 0 .. $#head;
      $newest_ami = (sort grep { /^\d+\.\d+-v\d+$/ } map { $_->[$ami] } @cells[1 .. $#cells])[-1] if defined $ami;
      for my $i (0 .. $#rows) {
        my $r = $rows[$i];
        # A section line: printed bold after a blank line, out of the columns.
        if ($r->[0] =~ /^## (.*)/) {
          print "";
          print $ENV{KLS_COLOR} eq "1" ? paint($1, "1;36") : $1;
          next;
        }
        my %row;
        @row{@head} = @$r;
        my $line = "";
        for my $j (0 .. $#$r) {
          my $v = $r->[$j];
          $line .= $ENV{KLS_COLOR} ne "1" ? $v : $i == 0 ? paint($v, 1) : cell($head[$j], $v, \%row);
          $line .= " " x ($width[$j] - length($v) + 2) if $j < $#$r;
        }
        print $line;
      }
    }'
}

# Tab completion. Namespaces and nodes are read from the cluster in the --context on the line, if any.
_kls() {
  local -a ctx
  local i
  for (( i = 1; i < ${#words}; i++ )); do
    case "${words[i]}" in
      --context=*) ctx=("${words[i]}") ;;
      --context) ctx=(--context "${words[i+1]}") ;;
    esac
  done
  # _arguments calls these with compadd options (-J, -M...), passed on as they are.
  _kls_complete_nodes() {
    compadd "$@" -- ${(f)"$(kubectl get nodes "${ctx[@]}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)"}
  }
  _kls_complete_namespaces() {
    compadd "$@" -- ${(f)"$(kubectl get namespaces "${ctx[@]}" -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)"}
  }
  _kls_complete_contexts() {
    compadd "$@" -- ${(f)"$(kubectl config get-contexts -o name 2>/dev/null)"}
  }
  _arguments -s \
    '(- *)'{-h,--help}'[show the help]' \
    '(--pods --node)--nodes[nodes table (the default)]' \
    '(--nodes)--pods[pods table]' \
    '(--nodes)--all[with --pods: also the namespaces hidden from developers]' \
    '--summary[add the summary table: per group with --nodes, per namespace with --pods]' \
    '--watch[redraw every N seconds until Ctrl+C]::seconds (2 by default):(1 2 5 10 30 60)' \
    '(--nodes)--node=-[with --pods: group by node, or with =NODE only the pods on that node]::node:_kls_complete_nodes' \
    '(-n --namespace -A --all-namespaces)'{-n+,--namespace=}'[namespace]:namespace:_kls_complete_namespaces' \
    '(-n --namespace -A --all-namespaces)'{-A,--all-namespaces}'[all namespaces]' \
    '(-l --selector)'{-l+,--selector=}'[label selector]:selector: ' \
    '--field-selector=[field selector]:selector: ' \
    '--context=[kubeconfig context]:context:_kls_complete_contexts' \
    '--kubeconfig=[kubeconfig file]:file:_files'
}
(( $+functions[compdef] )) && compdef _kls kls
