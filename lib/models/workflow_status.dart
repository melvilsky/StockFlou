enum WorkflowStatus {
  newFile,
  metadataReady,
  qcFailed,
  readyToUpload,
  uploaded,
  submitted,
}

extension WorkflowStatusX on WorkflowStatus {
  String get storageValue {
    switch (this) {
      case WorkflowStatus.newFile:
        return 'new';
      case WorkflowStatus.metadataReady:
        return 'metadata_ready';
      case WorkflowStatus.qcFailed:
        return 'qc_failed';
      case WorkflowStatus.readyToUpload:
        return 'ready_to_upload';
      case WorkflowStatus.uploaded:
        return 'uploaded';
      case WorkflowStatus.submitted:
        return 'submitted';
    }
  }

  String get label {
    switch (this) {
      case WorkflowStatus.newFile:
        return 'New';
      case WorkflowStatus.metadataReady:
        return 'Metadata Ready';
      case WorkflowStatus.qcFailed:
        return 'QC Failed';
      case WorkflowStatus.readyToUpload:
        return 'Ready to Upload';
      case WorkflowStatus.uploaded:
        return 'Uploaded';
      case WorkflowStatus.submitted:
        return 'Submitted';
    }
  }

  bool get canBeQueuedForUpload {
    return this == WorkflowStatus.readyToUpload ||
        this == WorkflowStatus.metadataReady;
  }
}

WorkflowStatus workflowStatusFromStorage(String? value) {
  switch (value) {
    case 'metadata_ready':
      return WorkflowStatus.metadataReady;
    case 'qc_failed':
      return WorkflowStatus.qcFailed;
    case 'ready_to_upload':
      return WorkflowStatus.readyToUpload;
    case 'uploaded':
      return WorkflowStatus.uploaded;
    case 'submitted':
      return WorkflowStatus.submitted;
    case 'new':
    default:
      return WorkflowStatus.newFile;
  }
}
