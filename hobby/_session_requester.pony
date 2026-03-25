trait tag _SessionRequester
  """
  Callback interface for the session store to deliver loaded session data.
  Implemented by `_Connection`.
  """
  be _session_loaded(session: SessionData val)
