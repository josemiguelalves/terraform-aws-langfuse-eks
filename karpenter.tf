# ------------------------------------------------------------------------------
# Karpenter – dedicated NodeClass and NodePool for Langfuse workloads.
# Nodes are tainted with storageType=efs:NoSchedule so only Langfuse pods
# (which carry the matching toleration) land here.
# ------------------------------------------------------------------------------

resource "kubectl_manifest" "langfuse_node_class" {
  force_new = true

  yaml_body = <<-YAML
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: ${local.name}
spec:
  amiFamily: AL2023
  amiSelectorTerms:
    - alias: al2023@latest
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        deleteOnTermination: true
        iops: 3000
        throughput: 125
        volumeSize: 25Gi
        volumeType: gp3
  role: ${var.node_instance_role_name}
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery/${var.eks_cluster_name}: ${var.eks_cluster_name}
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery/${var.eks_cluster_name}: ${var.eks_cluster_name}
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 2
    httpTokens: required
    instanceMetadataTags: enabled
  tags:
    IntentLabel: ${local.name}
    KarpenterProvisionerName: ${local.name}
    Name: ${var.eks_cluster_name}-${local.name}
    NodeType: ${local.name}
    Environment: ${var.environment}
    ManagedBy: terraform
  userData: |
    [settings.kubernetes]
    serializeImagePulls = false
YAML
}

resource "kubectl_manifest" "langfuse_node_pool" {
  depends_on = [kubectl_manifest.langfuse_node_class]

  force_new = true

  yaml_body = <<-YAML
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: ${local.name}
spec:
  disruption:
    consolidateAfter: 10m0s
    consolidationPolicy: WhenEmpty
    expireAfter: Never
  limits:
    cpu: ${var.node_pool_cpu_limit}
    memory: ${var.node_pool_memory_limit}
  template:
    metadata:
      labels:
        provisioner: ${local.name}
    spec:
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: ${local.name}
      requirements:
        - key: topology.kubernetes.io/zone
          operator: In
          values:
${join("\n", [for z in local.node_pool_availability_zones : "            - ${z}"])}
        - key: karpenter.sh/capacity-type
          operator: In
          values:
            - spot
            - on-demand
        - key: kubernetes.io/arch
          operator: In
          values:
            - amd64
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values:
${join("\n", [for c in var.node_pool_instance_categories : "            - ${c}"])}
        - key: karpenter.k8s.aws/instance-hypervisor
          operator: In
          values:
            - nitro
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values:
            - '5'
        - key: karpenter.k8s.aws/instance-cpu
          operator: In
          values:
            - '4'
            - '8'
            - '16'
            - '32'
        - key: kubernetes.io/os
          operator: In
          values:
            - linux
      taints:
        - effect: NoSchedule
          key: storageType
          value: efs
YAML
}
