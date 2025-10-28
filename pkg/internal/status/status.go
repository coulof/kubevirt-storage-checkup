/*
 * This file is part of the kiagnose project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * Copyright 2023 Red Hat, Inc.
 *
 */

package status

import (
	kstatus "github.com/kiagnose/kiagnose/kiagnose/status"
)

type Results struct {
	// Existing fields - DO NOT REMOVE (backward compatibility)
	OCPVersion string
	CNVVersion string

	// New platform fields
	Platform        string // "openshift" or "vanilla-k8s"
	K8sVersion      string // For vanilla K8s clusters
	KubeVirtVersion string // For vanilla K8s clusters

	// Existing storage fields
	DefaultStorageClass                       string
	PVCBound                                  string
	StorageProfilesWithEmptyClaimPropertySets string
	StorageProfilesWithSpecClaimPropertySets  string
	StorageProfilesWithSmartClone             string
	StorageProfilesWithRWX                    string
	StorageProfileMissingVolumeSnapshotClass  string
	GoldenImagesNotUpToDate                   string
	GoldenImagesNoDataSource                  string
	VMsWithNonVirtRbdStorageClass             string
	VMsWithUnsetEfsStorageClass               string
	VMBootFromGoldenImage                     string
	VMVolumeClone                             string
	VMLiveMigration                           string
	VMHotplugVolume                           string
	ConcurrentVMBoot                          string
}

type Status struct {
	kstatus.Status
	Results
}
