import subprocess
import re
import pathlib
import tempfile
import zipfile
import datetime

class Fastboot(object):
	def __init__(self):
		self.fastboot = "./resources/platform-tools/linux/fastboot"
		self.logfile = "./system.log"
		self.device   = None
		vno = self.get_version()
		if vno != None:
			self.available = True
		else:
			self.available = False
	
	def is_available(self):
		"""For checking if Fastboot is available on the system.

		Returns:
			boolean: Status on the presence in the system.
		"""
		return self.available

	def get_version(self):
		"""Checks the Fastboot version.

		Returns:
			string: The version number.
			None: Problem encountered trying to reach the executable.

		"""
		try:
			response = subprocess.run( [self.fastboot, "--version"], capture_output=True, text=True )
		except:
			return None

		return re.findall( "version\s*(.*)", str.splitlines( response.stdout)[0] )[0]
	
	def get_devices_connected(self):
		"""Gets the currently connected Android devices in Fastboot.

		Returns:
			Array: A list of Fastboot identifiers.
			None: No device connected/detected.
		"""
		devices  = []
		response = str.splitlines( subprocess.run( [self.fastboot, "devices"], capture_output=True, text=True ).stdout )
		if len( response ) == 0:
			return None

		for val in response:
			devices.append( str.split(val, '\t')[0] )

		return devices

	def set_device(self, device):
		"""Set the device to be worked on (get them using get_devices_connected()).

		Args:
			device (String): Device identifier from Fastboot devices.
		"""
		self.device = device

	def reboot_device(self):
		if self.device == None:
			return False
		
		subprocess.run( [self.fastboot, "reboot"] )

	def flash_ftf(self, file, mode):
		"""Flashes a sin file to the active fastboot device.

		Args:
			file (String): Location of sin file (will be extracted to TMP).
			mode (Int): 1 for boot, 2 for system, 3 for both, 4 for entire.

		Returns:
			Boolean: Success status.
		"""
		if self.device == None:
			return False
		
		fmode = []
		if mode == 1:
			fmode.append('boot')
		elif mode == 2:
			fmode.append('system')
		elif mode == 3:
			fmode.append('boot')
			fmode.append('system')
		elif mode == 4:
			fmode.append('boot')
			fmode.append('system')
			fmode.append('userdata')
		else:
			return False

		with tempfile.TemporaryDirectory() as dirpath:
			with zipfile.ZipFile(file, 'r') as zip_ref:
				zip_ref.extractall(dirpath)
				
				for partiton in fmode:
					if partiton == 'boot':
						self._flash_firmware(dirpath + '/kernel.sin', partiton)
					if partiton == 'system':
						self._flash_firmware(dirpath + '/system.sin', partiton)
					if partiton == 'userdata':
						self._flash_firmware(dirpath + '/userdata.sin', partiton)

		return True


	def _flash_firmware(self, file, partition):
		"""Flashes the specified file to the partition.

		Args:
			file (String): Path directly to the desired .sin or .img file.
			partition (String): Partition label.  

		Returns:
			[type]: [description]
		"""
		if self.device == None:
			return None
		
		return subprocess.run( [self.fastboot, "flash", partition, file], capture_output=True, text=True )

	def _log(self, message):
		f = open(self.logfile, "a")
		f.write( "[" + str(datetime.utcnow()) + "]: " + str(message) )
		f.close()